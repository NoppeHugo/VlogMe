import Foundation
import Combine

/// Bibliothèque de brouillons de vlogs.
///
/// Expose l'interface "brouillon actif" (segments, aspectRatio, url, newSegmentURL…) pour la
/// compatibilité avec CameraViewModel / ExportViewModel / PreviewViewModel. Fournit en plus
/// la gestion multi-brouillons (createDraft, activateDraft, setDefault, deleteDraft…).
@MainActor
final class VlogStore: ObservableObject {

    // MARK: - Proxy brouillon actif (compatible avec le code existant)

    @Published private(set) var segments: [VideoSegment] = []
    @Published var aspectRatio: AspectRatio = .vertical {
        didSet {
            guard !isSyncing else { return }
            updateActive { $0.aspectRatio = self.aspectRatio }
            save()
        }
    }

    // MARK: - État multi-brouillons

    @Published private(set) var drafts: [VlogDraft] = []
    @Published private(set) var activeId: UUID?
    @Published private(set) var defaultId: UUID?

    var activeDraft: VlogDraft? { drafts.first(where: { $0.id == activeId }) }
    var totalDuration: Double { segments.reduce(0) { $0 + $1.durationSeconds } }
    var hasSegments: Bool { !segments.isEmpty }
    var targetDuration: Double? { activeDraft?.targetDuration }
    var filterPreset: FilterPreset { activeDraft?.filterPreset ?? .none }

    // MARK: - Privé

    private let vlogsRoot: URL
    private let indexURL: URL
    private var isSyncing = false

    // MARK: - Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        vlogsRoot = docs.appendingPathComponent("vlogs", isDirectory: true)
        indexURL  = docs.appendingPathComponent("vlogs_index.json")
        try? FileManager.default.createDirectory(at: vlogsRoot, withIntermediateDirectories: true)
        load()
        if drafts.isEmpty {
            let d = newDraftInternal()
            defaultId = d.id
            save()
        }
    }

    // MARK: - Dossiers segments

    func segmentsDirectory(for draftId: UUID) -> URL {
        let dir = vlogsRoot
            .appendingPathComponent(draftId.uuidString, isDirectory: true)
            .appendingPathComponent("segments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Dossier segments du brouillon actif (compat SegmentStackView).
    var segmentsDirectory: URL {
        guard let id = activeId else { return vlogsRoot }
        return segmentsDirectory(for: id)
    }

    // MARK: - URLs (brouillon actif)

    func url(for segment: VideoSegment) -> URL {
        segmentsDirectory.appendingPathComponent(segment.fileName)
    }

    func url(for segment: VideoSegment, in draft: VlogDraft) -> URL {
        segmentsDirectory(for: draft.id).appendingPathComponent(segment.fileName)
    }

    func newSegmentURL() -> URL {
        segmentsDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    }

    // MARK: - Mutations segments (brouillon actif)

    func append(_ segment: VideoSegment) {
        updateActive { $0.segments.append(segment) }
        syncProxy()
        save()
    }

    func removeLast() {
        guard let last = segments.last else { return }
        delete(last)
    }

    func delete(_ segment: VideoSegment) {
        try? FileManager.default.removeItem(at: url(for: segment))
        updateActive { $0.segments.removeAll { $0.id == segment.id } }
        syncProxy()
        save()
    }

    /// Vide les segments du brouillon actif (segments déjà exportés).
    func clear() {
        guard let draft = activeDraft else { return }
        for seg in draft.segments {
            try? FileManager.default.removeItem(at: url(for: seg, in: draft))
        }
        updateActive { $0.segments = [] }
        syncProxy()
        save()
    }

    // MARK: - Gestion des brouillons

    @discardableResult
    func createDraft(name: String = "") -> VlogDraft {
        let d = newDraftInternal(name: name)
        save()
        return d
    }

    @discardableResult
    private func newDraftInternal(name: String = "") -> VlogDraft {
        var d = VlogDraft(name: name)
        if let current = activeDraft { d.aspectRatio = current.aspectRatio }
        _ = segmentsDirectory(for: d.id)
        drafts.append(d)
        activateInternal(d.id)
        return d
    }

    func activateDraft(_ id: UUID) {
        guard drafts.contains(where: { $0.id == id }) else { return }
        activateInternal(id)
        save()
    }

    func setDefault(_ id: UUID) {
        guard drafts.contains(where: { $0.id == id }) else { return }
        defaultId = id
        save()
    }

    func deleteDraft(_ id: UUID) {
        guard let draft = drafts.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: vlogsRoot.appendingPathComponent(draft.id.uuidString))
        drafts.removeAll { $0.id == id }
        if defaultId == id { defaultId = drafts.first?.id }
        if activeId == id {
            if let first = drafts.first { activateInternal(first.id) }
            else { newDraftInternal(); defaultId = activeId }
        }
        save()
    }

    func renameDraft(_ id: UUID, name: String) {
        mutate(id) { $0.name = name }
        save()
    }

    func updateFilter(_ preset: FilterPreset) {
        updateActive { $0.filterPreset = preset }
        save()
    }

    func setSegmentTrim(_ id: UUID, start: Double, end: Double?) {
        guard let draftIdx = drafts.firstIndex(where: { $0.id == activeId }),
              let segIdx = drafts[draftIdx].segments.firstIndex(where: { $0.id == id }) else { return }
        drafts[draftIdx].segments[segIdx].trimStart = start
        drafts[draftIdx].segments[segIdx].trimEnd   = end
        syncProxy()
        save()
    }

    func moveSegment(from source: IndexSet, to destination: Int) {
        updateActive { $0.segments.move(fromOffsets: source, toOffset: destination) }
        syncProxy()
        save()
    }

    func setMaxSegmentDuration(_ duration: Double?, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].maxSegmentDuration = duration
        save()
    }

    func setBackgroundMusic(path: String?, volume: Float = 0.3, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].backgroundMusicPath = path
        drafts[idx].backgroundMusicVolume = volume
        save()
    }

    func setIntro(style: IntroStyle, text: String, subtitle: String, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].introStyle = style
        drafts[idx].introText = text
        drafts[idx].introSubtitle = subtitle
        save()
    }

    func setHook(enabled: Bool, gap: Double, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].hookEnabled = enabled
        drafts[idx].hookGap = min(0.2, max(0.1, gap))
        save()
    }

    func setTransition(_ transition: TransitionStyle, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].transition = transition
        save()
    }

    func setOutro(enabled: Bool, text: String, subtitle: String, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].outroEnabled = enabled
        drafts[idx].outroText = text
        drafts[idx].outroSubtitle = subtitle
        save()
    }

    func setSticker(enabled: Bool, text: String, showDate: Bool, position: StickerPosition, style: StickerStyle, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].stickerEnabled = enabled
        drafts[idx].stickerText = text
        drafts[idx].stickerShowDate = showDate
        drafts[idx].stickerPosition = position
        drafts[idx].stickerStyle = style
        save()
    }

    func setBeatSync(_ enabled: Bool, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].beatSyncEnabled = enabled
        save()
    }

    /// Applique un template (pack cohérent) au brouillon actif.
    func applyTemplate(_ template: VlogTemplate) {
        updateActive { d in
            d.introStyle = template.introStyle
            if d.introText.trimmingCharacters(in: .whitespaces).isEmpty { d.introText = "vlog" }
            d.introSubtitle = template.introSubtitle
            d.filterPreset = template.filter
            d.transition = template.transition
            d.hookEnabled = template.hookEnabled
            d.hookGap = template.hookGap
            d.beatSyncEnabled = template.beatSync
        }
        save()
    }

    func backgroundMusicURL() -> URL? {
        guard let path = activeDraft?.backgroundMusicPath else { return nil }
        return segmentsDirectory.appendingPathComponent(path)
    }

    /// Met à jour la durée cible. Si `draftId` est fourni, modifie ce brouillon spécifique ;
    /// sinon met à jour le brouillon actif.
    func updateTargetDuration(_ duration: Double?, for draftId: UUID? = nil) {
        let id = draftId ?? activeId
        guard let id, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].targetDuration = duration
        save()
    }

    // MARK: - Helpers privés

    private func syncProxy() {
        isSyncing = true
        if let draft = activeDraft {
            segments = draft.segments
            aspectRatio = draft.aspectRatio
        } else {
            segments = []
            aspectRatio = .vertical
        }
        isSyncing = false
    }

    private func activateInternal(_ id: UUID) {
        activeId = id
        syncProxy()
    }

    private func updateActive(_ mutation: (inout VlogDraft) -> Void) {
        guard let id = activeId,
              let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        mutation(&drafts[idx])
    }

    private func mutate(_ id: UUID, _ fn: (inout VlogDraft) -> Void) {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        fn(&drafts[idx])
    }

    // MARK: - Persistance

    private struct LibraryIndex: Codable {
        var activeId: UUID?
        var defaultId: UUID?
        var drafts: [VlogDraft]
    }

    private func save() {
        let index = LibraryIndex(activeId: activeId, defaultId: defaultId, drafts: drafts)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: indexURL),
            let index = try? JSONDecoder().decode(LibraryIndex.self, from: data)
        else { return }

        drafts = index.drafts.map { draft in
            var d = draft
            let dir = segmentsDirectory(for: draft.id)
            d.segments = d.segments.filter {
                FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.fileName).path)
            }
            return d
        }
        defaultId = index.defaultId

        let targetId = index.activeId ?? defaultId ?? drafts.first?.id
        if let id = targetId, drafts.contains(where: { $0.id == id }) {
            activateInternal(id)
        } else if let first = drafts.first {
            activateInternal(first.id)
        }
    }
}
