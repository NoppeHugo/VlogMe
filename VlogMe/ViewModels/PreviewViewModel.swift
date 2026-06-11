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
    func build() async {
        state = .loading
        let urls = store.segments.map { store.url(for: $0) }
        guard !urls.isEmpty else {
            state = .failed("Aucun segment à prévisualiser.")
            return
        }
        do {
            // La prévisualisation joue les segments à 1080p, sans outro (WYSIWYG du tournage).
            let (composition, videoComposition) = try await VideoAssembler.build(
                urls: urls,
                renderSize: store.aspectRatio.renderSize
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
