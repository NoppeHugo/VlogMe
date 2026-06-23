import AVFoundation
import QuartzCore

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

/// Réglages du montage « hook » (tendance TikTok) : un aperçu rapide des premiers
/// clips, séparés par une courte pause, juste avant le vlog complet.
struct HookConfig {
    var gap: Double           // pause entre chaque clip (0.1 – 0.2 s)
    var clipDuration: Double  // durée de chaque extrait
    var maxClips: Int         // nombre d'extraits max

    init(gap: Double = 0.15, clipDuration: Double = 0.5, maxClips: Int = 5) {
        self.gap = min(0.2, max(0.1, gap))
        self.clipDuration = clipDuration
        self.maxClips = maxClips
    }
}

struct VideoAssembler {

    static func build(
        clips: [SegmentClip],
        renderSize: CGSize,
        cutSilence: Bool = false,
        introURL: URL? = nil,
        hook: HookConfig? = nil,
        transition: TransitionStyle = .none,
        outroURL: URL? = nil,
        stickerLayer: CALayer? = nil,
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

        // Intro stylée (carton de marque, plein clip)
        if let introURL {
            try await insertClip(
                url: introURL,
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

        // Hook : extraits courts des premiers clips, séparés par une pause noire
        if let hook {
            let count = min(hook.maxClips, clips.count)
            for clip in clips.prefix(count) {
                try await insertClip(
                    url: clip.url,
                    trimStart: clip.trimStart,
                    trimEnd: CMTimeAdd(clip.trimStart, CMTime(seconds: hook.clipDuration, preferredTimescale: 600)),
                    cutSilence: false,
                    isOutro: false,
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    renderSize: renderSize,
                    cursor: &cursor,
                    instructions: &instructions
                )
                insertGap(seconds: hook.gap, cursor: &cursor, instructions: &instructions)
            }
        }

        // Segments principaux (avec transitions entre clips)
        for (index, clip) in clips.enumerated() {
            // Flash blanc juste avant le clip (sauf le tout premier)
            if index > 0, transition.flashDuration > 0 {
                insertGap(
                    seconds: transition.flashDuration,
                    color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                    cursor: &cursor,
                    instructions: &instructions
                )
            }
            try await insertClip(
                url: clip.url,
                trimStart: clip.trimStart,
                trimEnd: clip.trimEnd,
                cutSilence: cutSilence,
                isOutro: false,
                transition: transition,
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

        // Sticker date / lieu incrusté sur tout le vlog (export uniquement)
        if let stickerLayer {
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            let parentLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            parentLayer.addSublayer(videoLayer)
            parentLayer.addSublayer(stickerLayer)
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }

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
        transition: TransitionStyle = .none,
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

        // Plage effective après trim (bornée à la durée réelle du clip)
        let effectiveStart = CMTimeMinimum(trimStart, duration)
        let effectiveEnd   = CMTimeMinimum(trimEnd ?? duration, duration)
        guard effectiveEnd > effectiveStart else { return }
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

        var isFirstRange = true
        for range in rangesToInsert {
            try videoTrack.insertTimeRange(range, of: assetVideoTrack, at: cursor)
            if let audioTrack, let assetAudioTrack {
                try? audioTrack.insertTimeRange(range, of: assetAudioTrack, at: cursor)
            }

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            // Rampe de transition au tout début du clip (zoom punch / whip)
            let ramp = isFirstRange ? transition.rampDuration : 0
            if ramp > 0, let startTransform = entryTransform(for: transition, base: transform, renderSize: renderSize) {
                let rampTime = CMTimeMinimum(CMTime(seconds: ramp, preferredTimescale: 600), range.duration)
                layerInstruction.setTransformRamp(
                    fromStart: startTransform,
                    toEnd: transform,
                    timeRange: CMTimeRange(start: cursor, duration: rampTime)
                )
            } else {
                layerInstruction.setTransform(transform, at: cursor)
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            cursor = cursor + range.duration
            isFirstRange = false
        }
    }

    /// Transform de départ d'une transition (l'arrivée étant le transform normal).
    private static func entryTransform(
        for transition: TransitionStyle,
        base: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform? {
        switch transition {
        case .none, .flash:
            return nil
        case .zoom:
            // Zoom supplémentaire autour du centre de rendu (se pose vers le transform normal).
            // scaleAboutCenter(q) = s·q + (1−s)·centre, appliqué après le transform de base.
            let s: CGFloat = 1.14
            let cx = renderSize.width / 2, cy = renderSize.height / 2
            let scaleAboutCenter = CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                                     tx: (1 - s) * cx, ty: (1 - s) * cy)
            return base.concatenating(scaleAboutCenter)
        case .whip:
            // Glissé horizontal rapide depuis la droite
            return base.concatenating(CGAffineTransform(translationX: renderSize.width * 0.6, y: 0))
        }
    }

    /// Insère une pause noire (trou dans les pistes) couverte par une instruction
    /// vide — rendue en noir par `AVVideoComposition`. Sert d'entracte entre les
    /// extraits du hook.
    private static func insertGap(
        seconds: Double,
        color: CGColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        cursor: inout CMTime,
        instructions: inout [AVMutableVideoCompositionInstruction]
    ) {
        guard seconds > 0 else { return }
        let duration = CMTime(seconds: seconds, preferredTimescale: 600)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
        instruction.backgroundColor = color
        instruction.layerInstructions = []
        instructions.append(instruction)
        cursor = cursor + duration
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
