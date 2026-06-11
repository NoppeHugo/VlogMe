import Foundation
import Combine

@MainActor
final class ExportViewModel: ObservableObject {

    enum State {
        case idle
        case exporting(Double)
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var saveMessage: String?
    @Published var showShareSheet = false

    private let store: VlogStore
    private let entitlements: Entitlements

    init(store: VlogStore, entitlements: Entitlements) {
        self.store = store
        self.entitlements = entitlements
    }

    var resolutionLabel: String { entitlements.exportResolution.label }

    var exportedURL: URL? {
        if case .ready(let url) = state { return url }
        return nil
    }

    // MARK: - Export

    func export() async {
        state = .exporting(0)
        let urls = store.segments.map { store.url(for: $0) }
        guard !urls.isEmpty else {
            state = .failed(ExportError.noSegments.localizedDescription)
            return
        }

        do {
            let renderSize = store.aspectRatio.renderSize(scale: entitlements.exportResolution.scale)
            let (composition, videoComposition) = try await VideoAssembler.build(
                urls: urls,
                renderSize: renderSize
            )
            let output = try await Exporter.export(
                composition: composition,
                videoComposition: videoComposition
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    if case .exporting = self.state { self.state = .exporting(progress) }
                }
            }
            state = .ready(output)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Destinations

    func saveToPhotos() async {
        guard let url = exportedURL else { return }
        do {
            try await PhotoSaver.save(url)
            saveMessage = "Enregistré dans Photos ✓"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    func share() {
        guard exportedURL != nil else { return }
        showShareSheet = true
    }
}
