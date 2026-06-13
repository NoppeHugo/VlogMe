import Foundation
import Combine
import UIKit
import AVFoundation

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
    @Published var filterPreset: FilterPreset
    @Published var cutSilence: Bool = false
    @Published var musicURL: URL? = nil
    @Published var musicVolume: Float = 0.3

    private let store: VlogStore
    private let entitlements: Entitlements
    private let notif = UINotificationFeedbackGenerator()

    init(store: VlogStore, entitlements: Entitlements) {
        self.store        = store
        self.entitlements = entitlements
        self.filterPreset = store.filterPreset
        self.musicURL     = store.backgroundMusicURL()
        self.musicVolume  = store.activeDraft?.backgroundMusicVolume ?? 0.3
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

    func setMusic(url: URL?, volume: Float) {
        musicURL    = url
        musicVolume = volume
        // Copier le fichier dans le dossier du draft si URL externe
        if let url {
            let dest = store.segmentsDirectory.appendingPathComponent("music_\(url.lastPathComponent)")
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: url, to: dest)
            }
            store.setBackgroundMusic(path: "music_\(url.lastPathComponent)", volume: volume)
            self.musicURL = dest
        } else {
            store.setBackgroundMusic(path: nil, volume: volume)
        }
    }

    func removeMusic() {
        musicURL = nil
        store.setBackgroundMusic(path: nil, volume: musicVolume)
    }

    // MARK: - Export

    func export() async {
        state = .exporting(0)
        let clips = store.segments.map { seg in
            SegmentClip(
                url: store.url(for: seg),
                trimStart: CMTime(seconds: seg.trimStart ?? 0, preferredTimescale: 600),
                trimEnd: seg.trimEnd.map { CMTime(seconds: $0, preferredTimescale: 600) }
            )
        }
        guard !clips.isEmpty else {
            state = .failed(ExportError.noSegments.localizedDescription)
            return
        }

        do {
            let renderSize = store.aspectRatio.renderSize(scale: entitlements.exportResolution.scale)
            let (composition, videoComposition, audioMix) = try await VideoAssembler.build(
                clips: clips,
                renderSize: renderSize,
                cutSilence: cutSilence,
                musicURL: musicURL,
                musicVolume: musicVolume
            )
            let output = try await Exporter.export(
                composition: composition,
                videoComposition: videoComposition,
                audioMix: audioMix,
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

    func shareToInstagram() {
        guard let url = exportedURL else { return }
        let pasteboardItems: [String: Any] = ["com.instagram.sharedSticker.backgroundVideo": try! Data(contentsOf: url)]
        UIPasteboard.general.setItems([pasteboardItems], options: [:])
        if let igURL = URL(string: "instagram-reels://shareToReels") {
            if UIApplication.shared.canOpenURL(igURL) {
                UIApplication.shared.open(igURL)
            } else {
                showShareSheet = true
            }
        }
    }

    func shareToTikTok() {
        guard exportedURL != nil else { return }
        showShareSheet = true
    }
}
