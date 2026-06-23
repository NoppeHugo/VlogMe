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

    // Intro stylée
    @Published var introStyle: IntroStyle
    @Published var introText: String
    @Published var introSubtitle: String
    // Hook montage (clips qui s'enchaînent)
    @Published var hookEnabled: Bool
    @Published var hookGap: Double

    private let store: VlogStore
    private let entitlements: Entitlements
    private let notif = UINotificationFeedbackGenerator()

    init(store: VlogStore, entitlements: Entitlements) {
        self.store        = store
        self.entitlements = entitlements
        self.filterPreset = store.filterPreset
        self.musicURL     = store.backgroundMusicURL()
        self.musicVolume  = store.activeDraft?.backgroundMusicVolume ?? 0.3
        self.introStyle   = store.activeDraft?.introStyle ?? .none
        self.introText    = store.activeDraft?.introText ?? "vlog"
        self.introSubtitle = store.activeDraft?.introSubtitle ?? ""
        self.hookEnabled  = store.activeDraft?.hookEnabled ?? false
        self.hookGap      = store.activeDraft?.hookGap ?? 0.15
    }

    var resolutionLabel: String { entitlements.exportResolution.label }
    var isPro: Bool { entitlements.isPro }

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

    func setIntro(style: IntroStyle, text: String, subtitle: String) {
        let styleChanged = style != introStyle
        introStyle = style
        introText = text
        introSubtitle = subtitle
        store.setIntro(style: style, text: text, subtitle: subtitle)
        if styleChanged {
            Analytics.track(.introConfigured, ["style": style.rawValue])
        }
    }

    func setHook(enabled: Bool, gap: Double) {
        let toggled = enabled != hookEnabled
        hookEnabled = enabled
        hookGap = gap
        store.setHook(enabled: enabled, gap: gap)
        if toggled {
            Analytics.track(.hookToggled, ["enabled": enabled])
        }
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

            // Intro stylée (filigrane « VlogMe » pour les non-Pro)
            var introURL: URL? = nil
            if introStyle.isEnabled {
                introURL = try? await IntroGenerator.intro(
                    style: introStyle,
                    title: introText,
                    subtitle: introSubtitle,
                    branded: !entitlements.isPro,
                    renderSize: renderSize
                )
            }
            let hook = hookEnabled ? HookConfig(gap: hookGap) : nil

            let (composition, videoComposition, audioMix) = try await VideoAssembler.build(
                clips: clips,
                renderSize: renderSize,
                cutSilence: cutSilence,
                introURL: introURL,
                hook: hook,
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
            Analytics.track(.vlogExported, [
                "segment_count": clips.count,
                "resolution": entitlements.exportResolution.label,
                "filter": filterPreset.label,
                "cut_silence": cutSilence,
                "has_music": musicURL != nil,
                "intro_style": introStyle.rawValue,
                "hook_enabled": hookEnabled
            ])
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
            Analytics.track(.savedToPhotos)
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
        Analytics.track(.sharedToInstagram)
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
        Analytics.track(.sharedToTikTok)
        showShareSheet = true
    }
}
