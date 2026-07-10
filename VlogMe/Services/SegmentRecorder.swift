import AVFoundation

/// Écrit un segment vidéo via `AVAssetWriter` à partir des buffers fournis par `CameraService`.
///
/// Contrairement à `AVCaptureMovieFileOutput`, la source vidéo peut changer en cours de
/// fichier (flip caméra, mode Duo) sans interrompre l'enregistrement.
/// Toutes les méthodes doivent être appelées depuis la même queue (la videoQueue du service) ;
/// seule la closure de `finish` est rappelée sur une queue arbitraire.
final class SegmentRecorder {

    enum RecorderError: Error {
        /// Segment sans aucune frame (arrêt quasi immédiat) : fichier abandonné.
        case cancelled
        case failed
    }

    let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private var didStartSession = false
    private var lastVideoTime = CMTime.invalid

    init?(url: URL, width: Int = 1080, height: Int = 1920) {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        self.writer = writer
        self.url = url

        // HEVC (H.265) plutôt que H.264 : ~2× plus efficace à qualité égale, encodage
        // matériel sur tous les iPhone iOS 17. Repli H.264 si jamais indisponible.
        let assistant = AVOutputSettingsAssistant(preset: .hevc1920x1080)
            ?? AVOutputSettingsAssistant(preset: .preset1920x1080)

        var videoSettings = assistant?.videoSettings ?? [AVVideoCodecKey: AVVideoCodecType.hevc]
        videoSettings[AVVideoWidthKey]  = width
        videoSettings[AVVideoHeightKey] = height

        // Débit plafonné (~6 Mbit/s en 1080p au lieu de ~10 par défaut) : les segments
        // prennent ≈ 2× moins de place sur disque et s'uploadent 2× plus vite dans les
        // vlogs partagés, sans perte visible pour du vlog. Keyframe toutes les 2 s.
        var compression = (videoSettings[AVVideoCompressionPropertiesKey] as? [String: Any]) ?? [:]
        compression[AVVideoAverageBitRateKey]          = Self.targetBitRate(width: width, height: height)
        compression[AVVideoExpectedSourceFrameRateKey] = 30
        compression[AVVideoMaxKeyFrameIntervalKey]     = 60
        videoSettings[AVVideoCompressionPropertiesKey] = compression

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        // Audio AAC 128 kbit/s : largement suffisant pour de la voix + ambiance.
        var audioSettings = assistant?.audioSettings
        audioSettings?[AVEncoderBitRateKey] = 128_000
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: nil
        )

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { return nil }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else { return nil }
    }

    /// Débit vidéo cible proportionnel à la surface : ≈ 0,1 bit/pixel/frame à 30 i/s
    /// (≈ 6,2 Mbit/s en 1080×1920), plancher à 4 Mbit/s.
    private static func targetBitRate(width: Int, height: Int) -> Int {
        max(4_000_000, Int(Double(width * height) * 30 * 0.1))
    }

    // MARK: - Ajout de frames

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard acceptVideo(at: time) else { return }
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(sampleBuffer)
        lastVideoTime = time
    }

    func appendVideo(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard acceptVideo(at: time) else { return }
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData else { return }
        pixelAdaptor.append(pixelBuffer, withPresentationTime: time)
        lastVideoTime = time
    }

    /// Ancre la timeline sur la première frame et impose des timestamps strictement
    /// croissants : au flip de caméra, la première frame de la nouvelle source peut
    /// être légèrement antérieure à la dernière écrite (déphasage entre capteurs).
    private func acceptVideo(at time: CMTime) -> Bool {
        startSessionIfNeeded(at: time)
        if lastVideoTime.isValid && time <= lastVideoTime { return false }
        return true
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        // L'audio n'est écrit qu'une fois la timeline ancrée sur la première frame vidéo.
        guard didStartSession, writer.status == .writing, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    private func startSessionIfNeeded(at time: CMTime) {
        guard !didStartSession, writer.status == .writing else { return }
        writer.startSession(atSourceTime: time)
        didStartSession = true
    }

    // MARK: - Finalisation

    func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        guard didStartSession, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            completion(.failure(RecorderError.cancelled))
            return
        }
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        let writer = self.writer
        let url = self.url
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(url))
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(.failure(writer.error ?? RecorderError.failed))
            }
        }
    }
}
