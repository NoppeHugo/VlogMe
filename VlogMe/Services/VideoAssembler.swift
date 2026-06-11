import AVFoundation

enum AssemblerError: LocalizedError {
    case noSegments
    case missingVideoTrack

    var errorDescription: String? {
        switch self {
        case .noSegments:       return "Aucun segment à assembler."
        case .missingVideoTrack: return "Impossible de créer la piste vidéo."
        }
    }
}

/// Concatène les segments en cuts secs et produit une composition lisible/exportable.
///
/// Phase 3 : on construit une `AVMutableComposition` + `AVMutableVideoComposition`
/// (format 9:16 / 16:9 via `renderSize`). La prévisualisation lit la composition
/// directement, sans ré-encoder — l'export (Phase 4) réutilisera ces mêmes objets.
struct VideoAssembler {

    /// - Parameters:
    ///   - urls: les segments, dans l'ordre.
    ///   - renderSize: la taille de rendu finale (selon format ET résolution d'export).
    ///   - outroURL: si fourni (utilisateur gratuit), l'outro de marque ajoutée à la fin (§8).
    static func build(
        urls: [URL],
        renderSize: CGSize,
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

        // L'outro (clip de marque, déjà rendu à `renderSize`) est traitée comme un segment final.
        let allURLs = outroURL.map { urls + [$0] } ?? urls

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for url in allURLs {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)

            guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                continue   // segment sans piste vidéo : on l'ignore plutôt que de tout casser
            }

            let range = CMTimeRange(start: .zero, duration: duration)
            try videoTrack.insertTimeRange(range, of: assetVideoTrack, at: cursor)

            if let audioTrack,
               let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: assetAudioTrack, at: cursor)
            }

            // Transform d'aspect-fill pour ce segment (gère l'orientation source).
            let preferredTransform = try await assetVideoTrack.load(.preferredTransform)
            let naturalSize = try await assetVideoTrack.load(.naturalSize)
            let transform = aspectFillTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                renderSize: renderSize
            )

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(transform, at: cursor)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            cursor = cursor + duration
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        return (composition, videoComposition)
    }

    /// Calcule la transform qui remplit `renderSize` (aspect-fill) en centrant la source,
    /// après application de son `preferredTransform` (rotation d'enregistrement).
    ///
    /// NB : c'est le point connu pour être délicat (cf. §11, risque « cadrage »).
    /// La logique est correcte pour les cas standards ; à valider sur device réel.
    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {

        // Taille telle qu'affichée une fois la rotation d'enregistrement appliquée.
        let displayedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(displayedRect.width), height: abs(displayedRect.height))

        guard displaySize.width > 0, displaySize.height > 0 else { return preferredTransform }

        let scale = max(renderSize.width / displaySize.width,
                        renderSize.height / displaySize.height)

        let scaledWidth = displaySize.width * scale
        let scaledHeight = displaySize.height * scale
        let tx = (renderSize.width - scaledWidth) / 2
        let ty = (renderSize.height - scaledHeight) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}
