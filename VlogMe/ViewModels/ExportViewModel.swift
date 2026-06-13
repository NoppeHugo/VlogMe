import Foundation
import Combine
import UIKit

@MainActor
final class ExportViewModel: ObservableObject {

    enum State {
        case idle           // configuration filtre + silence avant de lancer
        case exporting(Double)
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var saveMessage: String?
    @Published var showShareSheet = false

    @Published var filterPreset: FilterPreset
    @Published var cutSilence: Bool = false

    private let store: VlogStore
    private let entitlements: Entitlements
    private let notif = UINotificationFeedbackGenerator()

    init(store: VlogStore, entitlements: Entitlements) {
        self.store        = store
        self.entitlements = entitlements
        self.filterPreset = store.filterPreset
    }

    var resolutionLabel: String { entitlements.exportResolution.label }

    var exportedURL: URL? {
        if case .ready(let url) = state { return url }
        return nil
    }

    // MARK: - Configuration

    func setFilter(_ preset: FilterPreset) {
        filterPreset = preset
        store.updateFilter(preset)
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
                renderSize: renderSize,
                cutSilence: cutSilence
            )
            let output = try await Exporter.export(
                composition: composition,
                videoComposition: videoComposition,
                filterPreset: filterPreset
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    if case .exporting = self.state { self.state = .exporting(progress) }
                }
            }
            state = .ready(output)
            notif.notificationOccurred(.success)
        } catch {
            state = .failed(error.localizedDescription)
            notif.notificationOccurred(.error)
        }
    }

    // MARK: - Destinations

    func saveToPhotos() async {
        guard let url = exportedURL else { return }
        do {
            try await PhotoSaver.save(url)
            saveMessage = "Enregistré dans Photos ✓"
            notif.notificationOccurred(.success)
        } catch {
            saveMessage = error.localizedDescription
            notif.notificationOccurred(.error)
        }
    }

    func share() {
        guard exportedURL != nil else { return }
        showShareSheet = true
    }
}
