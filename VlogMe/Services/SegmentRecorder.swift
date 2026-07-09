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

        let assistant = AVOutputSettingsAssistant(preset: .preset1920x1080)

        var videoSettings = assistant?.videoSettings ?? [AVVideoCodecKey: AVVideoCodecType.h264]
        videoSettings[AVVideoWidthKey]  = width
        videoSettings[AVVideoHeightKey] = height
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: assistant?.audioSettings)
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
