import Foundation

struct VlogDraft: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var segments: [VideoSegment]
    var aspectRatio: AspectRatio
    var targetDuration: Double?
    var filterPreset: FilterPreset
    var maxSegmentDuration: Double?      // Auto-coupe après X sec (nil = infini)
    var backgroundMusicPath: String?     // Chemin relatif au dossier du draft
    var backgroundMusicVolume: Float     // 0.0 – 1.0

    init(name: String = "") {
        id = UUID()
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_FR")
        self.name = name.isEmpty ? "Vlog du \(f.string(from: Date()))" : name
        createdAt = Date()
        segments = []
        aspectRatio = .vertical
        targetDuration = nil
        filterPreset = .none
        maxSegmentDuration = nil
        backgroundMusicPath = nil
        backgroundMusicVolume = 0.3
    }

    var totalDuration: Double { segments.reduce(0) { $0 + $1.effectiveDuration } }
    var hasSegments: Bool { !segments.isEmpty }
}
