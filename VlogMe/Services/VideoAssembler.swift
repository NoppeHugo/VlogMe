import AVFoundation

enum AssemblerError: LocalizedError {
    case noSegments
    case missingVideoTrack

    var errorDescription: String? {
        switch self {
        case .noSegments:        return "Aucun segment à assembler."
        case .missingVideoTrack: return "Impossible de créer la piste vidéo."
        }
    }
}

/// Concatène les segments en cuts secs et produit une composition lisible/exportable.
struct VideoAssembler {

    /// - Parameters:
    ///   - urls: les segments, dans l'ordre.
    ///   - renderSize: la taille de rendu finale.
    ///   - cutSilence: si `true`, les plages silencieuses sont retirées avant l'assemblage.
    ///   - outroURL: clip de marque optionnel ajouté en fin (utilisateurs gratuits).
    static func build(
        urls: [URL],
        renderSize: CGSize,
        cutSilence: Bool = false,
        outroURL: URL? = nil
    ) async throws -> (composition: AVMutableComposition, videoComposition: AVMutableVideoComposition) {

        guard !urls.isEmpty else { throw AssemblerError.noSegments }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AssemblerError.missingVideoTrack }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let allURLs = outroURL.map { urls + [$0] } ?? urls

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for url in allURLs {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)

            guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                continue
            }

            let preferredTransform = try await assetVideoTrack.load(.preferredTransform)
            let naturalSize        = try await assetVideoTrack.load(.naturalSize)
            let transform = aspectFillTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                renderSize: renderSize
            )

            // Sous-plages à insérer (tout le segment, ou uniquement le non-silencieux)
            let isOutro = outroURL.map { $0 == url } ?? false
            let rangesToInsert: [CMTimeRange]
            if cutSilence && !isOutro {
                let nonSilent = await SilenceDetector.nonSilentRanges(in: url)
                rangesToInsert = nonSilent.isEmpty
                    ? [CMTimeRange(start: .zero, duration: duration)]
                    : nonSilent
            } else {
                rangesToInsert = [CMTimeRange(start: .zero, duration: duration)]
            }

            let assetAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first

            for range in rangesToInsert {
                try videoTrack.insertTimeRange(range, of: assetVideoTrack, at: cursor)

                if let audioTrack, let assetAudioTrack {
                    try? audioTrack.insertTimeRange(range, of: assetAudioTrack, at: cursor)
                }

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                layerInstruction.setTransform(transform, at: cursor)

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)

                cursor = cursor + range.duration
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        return (composition, videoComposition)
    }

    /// Calcule la transform aspect-fill (centre la source dans `renderSize`).
    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let displayedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(displayedRect.width), height: abs(displayedRect.height))

        guard displaySize.width > 0, displaySize.height > 0 else { return preferredTransform }

        let scale = max(renderSize.width / displaySize.width,
                        renderSize.height / displaySize.height)
        let tx = (renderSize.width  - displaySize.width  * scale) / 2
        let ty = (renderSize.height - displaySize.height * scale) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}
