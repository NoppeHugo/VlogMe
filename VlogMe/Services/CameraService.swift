import AVFoundation
import Combine

enum ZoomPreset: Double, CaseIterable {
    case ultraWide = 0.5
    case standard  = 1.0
    case tele      = 2.0

    var label: String {
        switch self {
        case .ultraWide: return ".5×"
        case .standard:  return "1×"
        case .tele:      return "2×"
        }
    }
}

final class CameraService: NSObject, ObservableObject {

    @Published private(set) var isRecording  = false
    @Published private(set) var facing: CameraFacing = .back
    @Published private(set) var isConfigured = false
    @Published private(set) var isTorchOn    = false
    @Published private(set) var zoomPreset: ZoomPreset = .standard
    @Published private(set) var hasUltraWide = false
    @Published var lastError: String?

    let session = AVCaptureSession()
    var onSegmentFinished: ((URL) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.hugonoppe.camera.session")
    private let movieOutput  = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var currentFacing: CameraFacing = .back
    private var didConfigure = false

    // Facteurs réels de videoZoomFactor pour chaque preset (calculés selon le device)
    private var presetFactors: [ZoomPreset: CGFloat] = [
        .ultraWide: 1.0,
        .standard:  1.0,
        .tele:      2.0
    ]

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

        if let device = Self.bestDevice(for: currentFacing),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            let factors = Self.computePresetFactors(for: device)
            let uw = factors[.ultraWide] != factors[.standard]
            publish {
                self.presetFactors = factors
                self.hasUltraWide  = uw
            }
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

    // MARK: - Switch camera (flip avant/arrière)

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            var newFacing = self.currentFacing
            newFacing.toggle()
            guard let newDevice = Self.bestDevice(for: newFacing),
                  let newInput  = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.session.beginConfiguration()
            if let current = self.videoInput { self.session.removeInput(current) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput    = newInput
                self.currentFacing = newFacing
                let factors = Self.computePresetFactors(for: newDevice)
                let uw = factors[.ultraWide] != factors[.standard]
                self.publish {
                    self.facing       = newFacing
                    self.isTorchOn    = false
                    self.zoomPreset   = .standard
                    self.presetFactors = factors
                    self.hasUltraWide = uw
                }
            } else if let current = self.videoInput {
                self.session.addInput(current)
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - Zoom preset (boutons .5× / 1× / 2×)

    func setZoomPreset(_ preset: ZoomPreset) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let factor = self.presetFactors[preset] ?? 1.0
            self.applyZoom(factor)
            self.publish { self.zoomPreset = preset }
        }
    }

    // MARK: - Zoom continu (pinch)

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyZoom(factor)
        }
    }

    private func applyZoom(_ factor: CGFloat) {
        guard let device = videoInput?.device else { return }
        try? device.lockForConfiguration()
        let lo  = device.minAvailableVideoZoomFactor
        let hi  = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        device.videoZoomFactor = max(lo, min(factor, hi))
        device.unlockForConfiguration()
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

    /// Sélectionne le meilleur device pour la position donnée.
    /// Pour la caméra arrière, préfère les devices virtuels (ultra-wide inclus).
    private static func bestDevice(for facing: CameraFacing) -> AVCaptureDevice? {
        let position = facing.avPosition
        if facing == .back {
            let types: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
            for type in types {
                if let d = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [type], mediaType: .video, position: position
                ).devices.first { return d }
            }
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    /// Calcule les facteurs videoZoomFactor pour chaque preset selon les switchOver du device.
    private static func computePresetFactors(for device: AVCaptureDevice) -> [ZoomPreset: CGFloat] {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        // switchOvers[0] = facteur où la caméra passe d'ultra-wide → wide
        // switchOvers[1] = facteur où la caméra passe de wide → télé
        if switchOvers.count >= 1 {
            let wideF = switchOvers[0]          // 1× correspond à ce facteur
            let teleF = switchOvers.count >= 2
                ? switchOvers[1]                // utilise le vrai télé si dispo
                : wideF * 2.0                   // sinon zoom numérique ×2 sur le wide
            return [
                .ultraWide: 1.0,   // minimum = ultra-wide
                .standard:  wideF,
                .tele:      teleF
            ]
        }
        // Pas de device virtuel : caméra wide seule
        return [
            .ultraWide: 1.0,
            .standard:  1.0,
            .tele:      2.0
        ]
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
