import AVFoundation
import Combine
import CoreMedia

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

/// Pipeline de capture.
///
/// Sur les appareils compatibles (tous les iPhone sous iOS 17), une `AVCaptureMultiCamSession`
/// fait tourner les caméras avant ET arrière en permanence tant que l'écran caméra est ouvert :
/// - le flip avant/arrière est instantané, y compris en plein enregistrement,
///   sans couper le segment en cours ;
/// - le mode Duo (PiP) incruste la caméra opposée en haut à gauche de la vidéo,
///   activable/désactivable à tout moment.
///
/// L'enregistrement passe par `AVAssetWriter` (voir `SegmentRecorder`) au lieu
/// d'`AVCaptureMovieFileOutput` : la source vidéo peut changer au milieu d'un fichier.
final class CameraService: NSObject, ObservableObject {

    // Publiés sur le main thread. `isRecording` bascule dès l'appel de start/stopRecording
    // pour que l'interface réagisse sans attendre le pipeline.
    @Published private(set) var isRecording  = false
    @Published private(set) var facing: CameraFacing = .back
    @Published private(set) var isConfigured = false
    @Published private(set) var isTorchOn    = false
    @Published private(set) var zoomPreset: ZoomPreset = .standard
    @Published private(set) var hasUltraWide = false
    @Published private(set) var isPiPEnabled = false
    @Published private(set) var supportsPiP  = false
    @Published var lastError: String?

    let session: AVCaptureSession
    /// Couche de prévisualisation de la caméra arrière (ou de la caméra active en mode mono-caméra).
    let backPreviewLayer: AVCaptureVideoPreviewLayer
    /// Couche de prévisualisation de la caméra avant (nil si le multicam n'est pas disponible).
    let frontPreviewLayer: AVCaptureVideoPreviewLayer?

    /// Appelée sur le main thread quand un segment est finalisé avec succès.
    var onSegmentFinished: ((URL) -> Void)?

    private let isMultiCam: Bool
    private let sessionQueue = DispatchQueue(label: "com.hugonoppe.camera.session")
    private let videoQueue   = DispatchQueue(label: "com.hugonoppe.camera.video")

    private struct CameraStream {
        let device: AVCaptureDevice
        let input: AVCaptureDeviceInput
        let output: AVCaptureVideoDataOutput
    }

    // Confiné à sessionQueue
    private var backStream: CameraStream?
    private var frontStream: CameraStream?
    private var audioInput: AVCaptureDeviceInput?
    private var didConfigure = false
    private var backIsVirtual = false
    private var backWideDevice: AVCaptureDevice?
    private var backUltraWideDevice: AVCaptureDevice?
    private var presetFactors: [ZoomPreset: CGFloat] = [.ultraWide: 1.0, .standard: 1.0, .tele: 2.0]

    private let audioOutput = AVCaptureAudioDataOutput()

    // Confiné à videoQueue
    private var backOutput: AVCaptureVideoDataOutput?
    private var frontOutput: AVCaptureVideoDataOutput?
    private var recorder: SegmentRecorder?
    /// Segments arrêtés qui drainent encore les dernières frames (latence de stabilisation).
    private var finishing: [(recorder: SegmentRecorder, cutoff: CMTime)] = []
    private var routeFacing: CameraFacing = .back
    private var routePiP = false
    private var latestBackBuffer: CVPixelBuffer?
    private var latestFrontBuffer: CVPixelBuffer?
    private let compositor = PiPCompositor()

    // MARK: - Init

    override init() {
        let multiCam = AVCaptureMultiCamSession.isMultiCamSupported
        isMultiCam = multiCam
        let session: AVCaptureSession = multiCam ? AVCaptureMultiCamSession() : AVCaptureSession()
        self.session = session
        backPreviewLayer  = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        frontPreviewLayer = multiCam ? AVCaptureVideoPreviewLayer(sessionWithNoConnection: session) : nil
        super.init()
        backPreviewLayer.videoGravity  = .resizeAspectFill
        frontPreviewLayer?.videoGravity = .resizeAspectFill
    }

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

        backStream = buildVideoStream(facing: .back, device: nil)
        if isMultiCam {
            frontStream = buildVideoStream(facing: .front, device: nil)
        }
        configureAudio()

        session.commitConfiguration()

        reduceCostIfNeeded()

        if backStream == nil { publishError("Caméra indisponible.") }
        detectBackCapabilities()
        refreshZoomState(for: .back)

        let backOut  = backStream?.output
        let frontOut = frontStream?.output
        videoQueue.async { [weak self] in
            self?.backOutput  = backOut
            self?.frontOutput = frontOut
        }

        let dual = backStream != nil && frontStream != nil
        publish {
            self.isConfigured = true
            self.supportsPiP  = dual
        }
    }

    /// Crée input + sortie vidéo + connexion preview pour une position donnée.
    /// À appeler sur sessionQueue, entre begin/commitConfiguration.
    private func buildVideoStream(facing: CameraFacing, device forced: AVCaptureDevice?) -> CameraStream? {
        guard let device = forced ?? Self.bestDevice(for: facing, multiCam: isMultiCam),
              let input  = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return nil }
        session.addInputWithNoConnections(input)

        guard let port = input.ports.first(where: { $0.mediaType == .video }) else {
            session.removeInput(input)
            return nil
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            return nil
        }
        session.addOutputWithNoConnections(output)

        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else {
            session.removeInput(input)
            session.removeOutput(output)
            return nil
        }
        session.addConnection(connection)
        configure(connection: connection, facing: facing)

        // En mono-caméra, la couche « back » sert de couche unique quelle que soit la position.
        let previewLayer: AVCaptureVideoPreviewLayer? = isMultiCam
            ? (facing == .back ? backPreviewLayer : frontPreviewLayer)
            : backPreviewLayer
        if let previewLayer {
            let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
            if session.canAddConnection(previewConnection) {
                session.addConnection(previewConnection)
                configure(connection: previewConnection, facing: facing)
            }
        }

        applyBestFormat(to: device)
        return CameraStream(device: device, input: input, output: output)
    }

    private func configure(connection: AVCaptureConnection, facing: CameraFacing) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if facing == .front, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        if connection.isVideoStabilizationSupported {
            // .standard : bonne stabilisation avec une latence de quelques frames seulement,
            // ce qui garde le démarrage/arrêt de segment réactif (cf. drainage dans stopRecording).
            connection.preferredVideoStabilizationMode = .standard
        }
    }

    private func configureAudio() {
        guard let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else { return }
        session.addInputWithNoConnections(input)
        audioInput = input

        audioOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(audioOutput),
              let port = input.ports.first(where: { $0.mediaType == .audio }) else { return }
        session.addOutputWithNoConnections(audioOutput)
        let connection = AVCaptureConnection(inputPorts: [port], output: audioOutput)
        if session.canAddConnection(connection) {
            session.addConnection(connection)
        }
    }

    private func applyBestFormat(to device: AVCaptureDevice) {
        guard let format = Self.bestFormat(for: device, multiCam: isMultiCam) else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let thirty = CMTime(value: 1, timescale: 30)
            device.activeVideoMinFrameDuration = thirty
            device.activeVideoMaxFrameDuration = thirty
            device.unlockForConfiguration()
        } catch {}
    }

    /// Si le couple de formats dépasse le budget matériel, redescend les deux caméras en 720p.
    private func reduceCostIfNeeded() {
        guard let multiSession = session as? AVCaptureMultiCamSession,
              multiSession.hardwareCost > 1.0 else { return }
        session.beginConfiguration()
        for device in [backStream?.device, frontStream?.device].compactMap({ $0 }) {
            guard let format = Self.bestFormat(for: device, multiCam: true, maxWidth: 1280) else { continue }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                let thirty = CMTime(value: 1, timescale: 30)
                device.activeVideoMinFrameDuration = thirty
                device.activeVideoMaxFrameDuration = thirty
                device.unlockForConfiguration()
            } catch {}
        }
        session.commitConfiguration()
    }

    // MARK: - Enregistrement

    /// Démarre un segment. À appeler depuis le main thread : `isRecording` bascule
    /// immédiatement, ce qui rend le bouton REC réactif et absorbe les double-taps.
    func startRecording(to url: URL) {
        guard !isRecording else { return }
        isRecording = true
        videoQueue.async { [weak self] in
            guard let self, self.recorder == nil else { return }
            guard let recorder = SegmentRecorder(url: url) else {
                self.publish {
                    self.isRecording = false
                    self.lastError = "Impossible de démarrer l'enregistrement."
                }
                return
            }
            self.recorder = recorder
        }
    }

    /// Arrête le segment en cours. Les frames encore dans le pipeline de stabilisation
    /// sont drainées jusqu'à l'instant d'arrêt avant la finalisation du fichier.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        let clock = session.synchronizationClock ?? CMClockGetHostTimeClock()
        let cutoff = CMClockGetTime(clock)
        videoQueue.async { [weak self] in
            guard let self, let recorder = self.recorder else { return }
            self.recorder = nil
            self.finishing.append((recorder, cutoff))
            // Filet de sécurité si plus aucune frame n'arrive (session stoppée, etc.)
            self.videoQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self,
                      let index = self.finishing.firstIndex(where: { $0.recorder === recorder }) else { return }
                self.finishing.remove(at: index)
                self.finalize(recorder)
            }
        }
    }

    private func finalize(_ recorder: SegmentRecorder) {
        recorder.finish { [weak self] result in
            self?.publish {
                switch result {
                case .success(let url):
                    self?.onSegmentFinished?(url)
                case .failure(let error):
                    // Un segment sans aucune frame (tap démarrer/arrêter quasi simultané)
                    // est simplement abandonné, sans message d'erreur.
                    if case SegmentRecorder.RecorderError.cancelled = error { return }
                    self?.lastError = "Enregistrement interrompu : \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Flip avant/arrière

    /// Change de caméra. Avec le multicam, la bascule est instantanée et ne coupe pas
    /// le segment en cours : seule la source des frames envoyées au fichier change.
    func switchCamera() {
        var newFacing = facing
        newFacing.toggle()

        guard isMultiCam else {
            legacySwitchCamera(to: newFacing)
            return
        }

        facing     = newFacing
        isTorchOn  = false
        zoomPreset = .standard

        videoQueue.async { [weak self] in self?.routeFacing = newFacing }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setTorch(on: false)
            // La caméra arrière revient sur son module standard pour la prochaine fois.
            if newFacing == .back, !self.backIsVirtual,
               let wide = self.backWideDevice, self.backStream?.device !== wide {
                self.session.beginConfiguration()
                self.swapBackDevice(to: wide)
                self.session.commitConfiguration()
            }
            self.refreshZoomState(for: newFacing)
            if let device = self.device(for: newFacing) {
                self.applyZoom(self.presetFactors[.standard] ?? 1.0, to: device, animated: false)
            }
        }
    }

    /// Bascule mono-caméra (appareils sans multicam) : on remplace l'entrée vidéo.
    /// L'enregistrement en cours continue dans le même fichier — les frames reprennent
    /// dès que la nouvelle caméra est prête.
    private func legacySwitchCamera(to newFacing: CameraFacing) {
        sessionQueue.async { [weak self] in
            guard let self, let old = self.backStream else { return }
            self.session.beginConfiguration()
            self.session.removeInput(old.input)
            self.session.removeOutput(old.output)
            self.backStream = self.buildVideoStream(facing: newFacing, device: nil)
            self.session.commitConfiguration()

            self.detectBackCapabilities()
            self.refreshZoomState(for: newFacing)

            let out = self.backStream?.output
            self.videoQueue.async { [weak self] in self?.backOutput = out }
            self.publish {
                self.facing     = newFacing
                self.isTorchOn  = false
                self.zoomPreset = .standard
            }
        }
    }

    // MARK: - Mode Duo (PiP)

    /// Active/désactive l'incrustation de la caméra opposée en haut à gauche.
    /// Fonctionne aussi en plein enregistrement.
    func setPiP(_ enabled: Bool) {
        guard supportsPiP else { return }
        isPiPEnabled = enabled
        videoQueue.async { [weak self] in self?.routePiP = enabled }
    }

    // MARK: - Zoom

    func setZoomPreset(_ preset: ZoomPreset) {
        let target = facing
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if target == .back, self.isMultiCam, !self.backIsVirtual, let wide = self.backWideDevice {
                // Caméra arrière physique : le .5× se fait en changeant de module.
                let desired = (preset == .ultraWide) ? (self.backUltraWideDevice ?? wide) : wide
                let needsSwap = self.backStream?.device !== desired
                if needsSwap {
                    self.session.beginConfiguration()
                    self.swapBackDevice(to: desired)
                    self.session.commitConfiguration()
                }
                if let device = self.backStream?.device {
                    self.applyZoom(preset == .tele ? 2.0 : 1.0, to: device, animated: !needsSwap)
                }
            } else if let device = self.device(for: target) {
                self.applyZoom(self.presetFactors[preset] ?? 1.0, to: device, animated: true)
            }
            self.publish { self.zoomPreset = preset }
        }
    }

    func setZoom(_ factor: CGFloat) {
        let target = facing
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device(for: target) else { return }
            self.applyZoom(factor, to: device, animated: false)
        }
    }

    private func applyZoom(_ factor: CGFloat, to device: AVCaptureDevice, animated: Bool) {
        try? device.lockForConfiguration()
        let lo      = device.minAvailableVideoZoomFactor
        let hi      = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let clamped = max(lo, min(factor, hi))
        if animated {
            device.ramp(toVideoZoomFactor: clamped, withRate: 6.0)
        } else {
            device.videoZoomFactor = clamped
        }
        device.unlockForConfiguration()
    }

    /// Remplace le module de la caméra arrière (wide ↔ ultra-wide) sans arrêter la session
    /// ni l'enregistrement en cours. À appeler sur sessionQueue, entre begin/commit.
    private func swapBackDevice(to device: AVCaptureDevice) {
        guard let old = backStream, old.device !== device else { return }
        session.removeInput(old.input)
        session.removeOutput(old.output)
        backStream = buildVideoStream(facing: .back, device: device)
        let out = backStream?.output
        videoQueue.async { [weak self] in self?.backOutput = out }
    }

    /// Détermine, pour la caméra arrière courante, si le zoom passe par un device virtuel
    /// (bascule optique automatique) ou par un échange de modules physiques.
    private func detectBackCapabilities() {
        guard let device = backStream?.device else { return }
        backIsVirtual = !device.virtualDeviceSwitchOverVideoZoomFactors.isEmpty
        if backIsVirtual {
            backWideDevice = nil
            backUltraWideDevice = nil
        } else {
            backWideDevice = device
            backUltraWideDevice = isMultiCam
                ? AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back
                  ).devices.first(where: { Self.bestFormat(for: $0, multiCam: true) != nil })
                : nil
        }
    }

    private func refreshZoomState(for facing: CameraFacing) {
        guard let device = device(for: facing) else { return }
        let factors   = Self.computePresetFactors(for: device)
        let virtualUW = factors[.ultraWide] != factors[.standard]
        presetFactors = factors
        let ultra = facing == .back && (virtualUW || backUltraWideDevice != nil)
        publish { self.hasUltraWide = ultra }
    }

    /// Appareil qui alimente l'image principale pour une position donnée. (sessionQueue)
    private func device(for facing: CameraFacing) -> AVCaptureDevice? {
        guard isMultiCam else { return backStream?.device }
        return facing == .back ? backStream?.device : frontStream?.device
    }

    // MARK: - Tap to focus + expose

    func focusAndExpose(at devicePoint: CGPoint) {
        let target = facing
        sessionQueue.async { [weak self] in
            guard let device = self?.device(for: target) else { return }
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
            guard let self, let device = self.backStream?.device,
                  device.hasTorch, device.isTorchAvailable else { return }
            try? device.lockForConfiguration()
            device.torchMode = device.torchMode == .off ? .on : .off
            let isOn = device.torchMode == .on
            device.unlockForConfiguration()
            self.publish { self.isTorchOn = isOn }
        }
    }

    /// (sessionQueue)
    private func setTorch(on: Bool) {
        guard let device = backStream?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: - Sélection device / format

    /// Sélectionne le meilleur device pour la position donnée.
    /// Pour l'arrière, préfère les devices virtuels (bascule optique automatique) quand
    /// leurs formats sont exploitables — en multicam, seuls certains formats le sont.
    private static func bestDevice(for facing: CameraFacing, multiCam: Bool) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = facing == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: facing.avPosition
        ).devices
        return devices.first { bestFormat(for: $0, multiCam: multiCam) != nil }
    }

    /// Meilleur format 30 fps ≤ maxWidth (1080p de préférence, binned pour limiter la chauffe).
    private static func bestFormat(
        for device: AVCaptureDevice,
        multiCam: Bool,
        maxWidth: Int32 = 1920
    ) -> AVCaptureDevice.Format? {
        var best: AVCaptureDevice.Format?
        var bestScore = Int.min
        for format in device.formats {
            if multiCam && !format.isMultiCamSupported { continue }
            let desc = format.formatDescription
            guard CMFormatDescriptionGetMediaSubType(desc) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { continue }
            guard format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }) else { continue }
            let dim = CMVideoFormatDescriptionGetDimensions(desc)
            guard dim.width <= maxWidth else { continue }

            var score = 0
            if dim.width == 1920 && dim.height == 1080 {
                score += 1000
            } else {
                score -= abs(Int(dim.width) - 1920)
            }
            if format.isVideoBinned { score += 500 }
            if score > bestScore {
                bestScore = score
                best = format
            }
        }
        return best
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

// MARK: - Réception des frames (videoQueue)

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === audioOutput {
            recorder?.appendAudio(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let source: CameraFacing
        if output === backOutput {
            source = .back
            latestBackBuffer = pixelBuffer
        } else if output === frontOutput {
            source = .front
            latestFrontBuffer = pixelBuffer
        } else {
            return
        }

        guard source == routeFacing, recorder != nil || !finishing.isEmpty else { return }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // En mode Duo, la caméra opposée est incrustée dans l'image écrite.
        var composed: CVPixelBuffer?
        if routePiP, let overlay = (source == .back ? latestFrontBuffer : latestBackBuffer) {
            composed = compositor.compose(main: pixelBuffer, overlay: overlay)
        }

        func deliver(to recorder: SegmentRecorder) {
            if let composed {
                recorder.appendVideo(pixelBuffer: composed, at: time)
            } else {
                recorder.appendVideo(sampleBuffer)
            }
        }

        if let recorder { deliver(to: recorder) }

        if !finishing.isEmpty {
            for entry in finishing {
                if time <= entry.cutoff {
                    deliver(to: entry.recorder)
                } else {
                    finalize(entry.recorder)
                }
            }
            finishing.removeAll { time > $0.cutoff }
        }
    }
}
