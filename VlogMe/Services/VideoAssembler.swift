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

// Représente un segment avec ses points de trim optionnels
struct SegmentClip {
    let url: URL
    let trimStart: CMTime    // .zero = pas de trim début
    let trimEnd: CMTime?     // nil = jusqu'à la fin
}

struct VideoAssembler {

    static func build(
        clips: [SegmentClip],
        renderSize: CGSize,
        cutSilence: Bool = false,
        outroURL: URL? = nil,
        musicURL: URL? = nil,
        musicVolume: Float = 0.3
    ) async throws -> (composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix?) {

        guard !clips.isEmpty else { throw AssemblerError.noSegments }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AssemblerError.missingVideoTrack }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        // Segments principaux
        for clip in clips {
            try await insertClip(
                url: clip.url,
                trimStart: clip.trimStart,
                trimEnd: clip.trimEnd,
                cutSilence: cutSilence,
                isOutro: false,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                renderSize: renderSize,
                cursor: &cursor,
                instructions: &instructions
            )
        }

        // Outro optionnel (plein clip, sans trim ni silence)
        if let outroURL {
            try await insertClip(
                url: outroURL,
                trimStart: .zero,
                trimEnd: nil,
                cutSilence: false,
                isOutro: true,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                renderSize: renderSize,
                cursor: &cursor,
                instructions: &instructions
            )
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        // Musique de fond
        let audioMix = try await addBackgroundMusic(
            musicURL: musicURL,
            volume: musicVolume,
            videoDuration: cursor,
            to: composition
        )

        return (composition, videoComposition, audioMix)
    }

    // MARK: - Insert helpers

    private static func insertClip(
        url: URL,
        trimStart: CMTime,
        trimEnd: CMTime?,
        cutSilence: Bool,
        isOutro: Bool,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack?,
        renderSize: CGSize,
        cursor: inout CMTime,
        instructions: inout [AVMutableVideoCompositionInstruction]
    ) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }

        let preferredTransform = try await assetVideoTrack.load(.preferredTransform)
        let naturalSize        = try await assetVideoTrack.load(.naturalSize)
        let transform = aspectFillTransform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            renderSize: renderSize
        )

        // Plage effective après trim
        let effectiveStart = trimStart
        let effectiveEnd   = trimEnd ?? duration
        let effectiveRange = CMTimeRange(start: effectiveStart, end: effectiveEnd)

        // Sous-plages (coupe silence ou plage entière)
        let rangesToInsert: [CMTimeRange]
        if cutSilence && !isOutro {
            let nonSilent = await SilenceDetector.nonSilentRanges(in: url)
            // Intersectionner avec la plage trimmée
            let trimmedNonSilent = nonSilent.compactMap { $0.intersection(effectiveRange) }
            rangesToInsert = trimmedNonSilent.isEmpty
                ? [effectiveRange]
                : trimmedNonSilent
        } else {
            rangesToInsert = [effectiveRange]
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

    private static func addBackgroundMusic(
        musicURL: URL?,
        volume: Float,
        videoDuration: CMTime,
        to composition: AVMutableComposition
    ) async throws -> AVMutableAudioMix? {
        guard let musicURL, videoDuration > .zero else { return nil }
        let musicAsset = AVURLAsset(url: musicURL)
        guard let musicAudioTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first else { return nil }
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        let musicDuration  = (try? await musicAsset.load(.duration)) ?? .zero
        let insertDuration = CMTimeMinimum(musicDuration, videoDuration)
        guard insertDuration > .zero else { return nil }

        try? track.insertTimeRange(
            CMTimeRange(start: .zero, duration: insertDuration),
            of: musicAudioTrack,
            at: .zero
        )

        // Fade out sur les 2 dernières secondes
        let fadeStart = CMTimeSubtract(insertDuration, CMTime(seconds: 2, preferredTimescale: 600))
        let params = AVMutableAudioMixInputParameters(track: track)
        params.setVolume(volume, at: .zero)
        if fadeStart > .zero {
            params.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0, timeRange: CMTimeRange(start: fadeStart, duration: CMTime(seconds: 2, preferredTimescale: 600)))
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [params]
        return audioMix
    }

    // MARK: - Transform

    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let displayedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(displayedRect.width), height: abs(displayedRect.height))
        guard displaySize.width > 0, displaySize.height > 0 else { return preferredTransform }
        let scale = max(renderSize.width / displaySize.width, renderSize.height / displaySize.height)
        let tx = (renderSize.width  - displaySize.width  * scale) / 2
        let ty = (renderSize.height - displaySize.height * scale) / 2
        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}
