import Foundation
import AVFoundation
import Combine

/// Logique de l'écran Prévisualisation (cf. §4, écran 2).
@MainActor
final class PreviewViewModel: ObservableObject {

    enum State {
        case loading
        case ready(AVPlayer)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    private let store: VlogStore

    init(store: VlogStore) {
        self.store = store
    }

    /// Assemble les segments et prépare un lecteur sur la composition (sans ré-encodage).
    ///
    /// L'intro stylée et le hook sont inclus dès la prévisualisation : c'est le
    /// « teaser » offert à tous (même gratuits) pour donner envie de passer à Pro.
    /// `isPro` n'enlève que le filigrane de marque.
    func build(isPro: Bool = false) async {
        state = .loading
        let clips = store.segments.map { seg in
            SegmentClip(
                url: store.url(for: seg),
                trimStart: CMTime(seconds: seg.trimStart ?? 0, preferredTimescale: 600),
                trimEnd: seg.trimEnd.map { CMTime(seconds: $0, preferredTimescale: 600) }
            )
        }
        guard !clips.isEmpty else {
            state = .failed("Aucun segment à prévisualiser.")
            return
        }
        do {
            let renderSize = store.aspectRatio.renderSize

            var introURL: URL? = nil
            if let draft = store.activeDraft, draft.introStyle.isEnabled {
                introURL = try? await IntroGenerator.intro(
                    style: draft.introStyle,
                    title: draft.introText,
                    subtitle: draft.introSubtitle,
                    branded: !isPro,
                    renderSize: renderSize
                )
            }
            let hook = (store.activeDraft?.hookEnabled ?? false)
                ? HookConfig(gap: store.activeDraft?.hookGap ?? 0.15)
                : nil

            let (composition, videoComposition, _) = try await VideoAssembler.build(
                clips: clips,
                renderSize: renderSize,
                introURL: introURL,
                hook: hook
            )
            let item = AVPlayerItem(asset: composition)
            item.videoComposition = videoComposition
            let player = AVPlayer(playerItem: item)
            state = .ready(player)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
