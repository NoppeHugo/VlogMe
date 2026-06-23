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
    // Transitions entre clips
    @Published var transition: TransitionStyle
    // Outro / CTA
    @Published var outroEnabled: Bool
    @Published var outroText: String
    @Published var outroSubtitle: String
    // Sticker date / lieu
    @Published var stickerEnabled: Bool
    @Published var stickerText: String
    @Published var stickerShowDate: Bool
    @Published var stickerPosition: StickerPosition
    @Published var stickerStyle: StickerStyle
    // Beat-sync
    @Published var beatSyncEnabled: Bool

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
        self.transition   = store.activeDraft?.transition ?? .none
        self.outroEnabled = store.activeDraft?.outroEnabled ?? false
        self.outroText    = store.activeDraft?.outroText ?? ""
        self.outroSubtitle = store.activeDraft?.outroSubtitle ?? "abonne-toi"
        self.stickerEnabled = store.activeDraft?.stickerEnabled ?? false
        self.stickerText  = store.activeDraft?.stickerText ?? ""
        self.stickerShowDate = store.activeDraft?.stickerShowDate ?? false
        self.stickerPosition = store.activeDraft?.stickerPosition ?? .topLeading
        self.stickerStyle = store.activeDraft?.stickerStyle ?? .pill
        self.beatSyncEnabled = store.activeDraft?.beatSyncEnabled ?? false
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

    func setTransition(_ t: TransitionStyle) {
        let changed = t != transition
        transition = t
        store.setTransition(t)
        if changed { Analytics.track(.transitionSelected, ["style": t.rawValue]) }
    }

    func setOutro(enabled: Bool, text: String, subtitle: String) {
        outroEnabled = enabled
        outroText = text
        outroSubtitle = subtitle
        store.setOutro(enabled: enabled, text: text, subtitle: subtitle)
    }

    func setSticker(enabled: Bool, text: String, showDate: Bool, position: StickerPosition, style: StickerStyle) {
        stickerEnabled = enabled
        stickerText = text
        stickerShowDate = showDate
        stickerPosition = position
        stickerStyle = style
        store.setSticker(enabled: enabled, text: text, showDate: showDate, position: position, style: style)
    }

    func setBeatSync(_ enabled: Bool) {
        beatSyncEnabled = enabled
        store.setBeatSync(enabled)
        Analytics.track(.beatSyncToggled, ["enabled": enabled])
    }

    /// Applique un template et resynchronise l'état local.
    func applyTemplate(_ template: VlogTemplate) {
        store.applyTemplate(template)
        introStyle    = store.activeDraft?.introStyle ?? introStyle
        introText     = store.activeDraft?.introText ?? introText
        introSubtitle = store.activeDraft?.introSubtitle ?? introSubtitle
        filterPreset  = store.activeDraft?.filterPreset ?? filterPreset
        transition    = store.activeDraft?.transition ?? transition
        hookEnabled   = store.activeDraft?.hookEnabled ?? hookEnabled
        hookGap       = store.activeDraft?.hookGap ?? hookGap
        beatSyncEnabled = store.activeDraft?.beatSyncEnabled ?? beatSyncEnabled
        Analytics.track(.templateApplied, ["template": template.id])
    }

    /// Texte du sticker tel qu'il sera incrusté (date + texte libre).
    var stickerDisplayText: String {
        StickerRenderer.displayText(
            text: stickerText,
            showDate: stickerShowDate,
            date: store.activeDraft?.createdAt ?? Date()
        )
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

            let branded = !entitlements.isPro

            // Intro stylée (filigrane « VlogMe » pour les non-Pro)
            var introURL: URL? = nil
            if introStyle.isEnabled {
                introURL = try? await IntroGenerator.intro(
                    style: introStyle,
                    title: introText,
                    subtitle: introSubtitle,
                    branded: branded,
                    renderSize: renderSize
                )
            }

            // Outro / CTA assorti à l'intro
            var outroURL: URL? = nil
            if outroEnabled {
                outroURL = try? await IntroGenerator.outro(
                    style: introStyle.isEnabled ? introStyle : .minimal,
                    title: outroText,
                    subtitle: outroSubtitle,
                    branded: branded,
                    renderSize: renderSize
                )
            }

            // Hook (éventuellement calé sur le beat de la musique)
            var hook: HookConfig? = hookEnabled ? HookConfig(gap: hookGap) : nil
            if hookEnabled, beatSyncEnabled, let musicURL,
               let bpm = await BeatDetector.estimateBPM(url: musicURL) {
                let beat = BeatDetector.beatDuration(bpm: bpm)
                hook = HookConfig(gap: 0, clipDuration: beat, maxClips: 6)
            }

            // Sticker date / lieu
            var stickerLayer: CALayer? = nil
            if stickerEnabled {
                stickerLayer = StickerRenderer.makeLayer(
                    text: stickerDisplayText,
                    renderSize: renderSize,
                    position: stickerPosition,
                    style: stickerStyle
                )
            }

            let (composition, videoComposition, audioMix) = try await VideoAssembler.build(
                clips: clips,
                renderSize: renderSize,
                cutSilence: cutSilence,
                introURL: introURL,
                hook: hook,
                transition: transition,
                outroURL: outroURL,
                stickerLayer: stickerLayer,
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
                "hook_enabled": hookEnabled,
                "transition": transition.rawValue,
                "outro_enabled": outroEnabled,
                "sticker_enabled": stickerEnabled,
                "beat_sync": beatSyncEnabled
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
