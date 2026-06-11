import AVFoundation
import Combine

final class CameraService: NSObject, ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var facing: CameraFacing = .back
    @Published private(set) var isConfigured = false
    @Published private(set) var isTorchOn = false
    @Published var lastError: String?

    let session = AVCaptureSession()
    var onSegmentFinished: ((URL) -> Void)?

    private let sessionQueue = DispatchQueue(label: "pro.vlogme.camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var currentFacing: CameraFacing = .back
    private var didConfigure = false

    // MARK: - Session lifecycle

    func configure() {
        sessionQueue.async { [weak self] in self?.configureSession() }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSession() {
        guard !didConfigure else { return }
        didConfigure = true

        session.beginConfiguration()
        session.sessionPreset = .high

        if let device = Self.device(for: currentFacing),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        } else {
            publishError("Caméra indisponible.")
        }

        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        publish { self.isConfigured = true }
    }

    // MARK: - Recording

    func startRecording(to url: URL) {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if self.currentFacing == .front, connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    // MARK: - Switch camera

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            var newFacing = self.currentFacing
            newFacing.toggle()
            guard let newDevice = Self.device(for: newFacing),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
            self.session.beginConfiguration()
            if let current = self.videoInput { self.session.removeInput(current) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.currentFacing = newFacing
                self.publish { self.facing = newFacing; self.isTorchOn = false }
            } else if let current = self.videoInput {
                self.session.addInput(current)
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            try? device.lockForConfiguration()
            let clamped = max(1.0, min(factor, min(device.activeFormat.videoMaxZoomFactor, 10.0)))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        }
    }

    // MARK: - Tap to focus + expose

    func focusAndExpose(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: - Torch

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device,
                  device.hasTorch, device.isTorchAvailable else { return }
            try? device.lockForConfiguration()
            device.torchMode = device.torchMode == .off ? .on : .off
            let isOn = device.torchMode == .on
            device.unlockForConfiguration()
            self?.publish { self?.isTorchOn = isOn }
        }
    }

    // MARK: - Helpers

    private static func device(for facing: CameraFacing) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: facing.avPosition
        ).devices.first
    }

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    private func publishError(_ message: String) {
        publish { self.lastError = message }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        publish { self.isRecording = true }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        publish {
            self.isRecording = false
            if let error {
                let nsError = error as NSError
                let ok = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
                if !ok { self.lastError = "Enregistrement interrompu : \(error.localizedDescription)" }
            }
            self.onSegmentFinished?(outputFileURL)
        }
    }
}
