import Foundation

struct VlogDraft: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var segments: [VideoSegment]
    var aspectRatio: AspectRatio
    var targetDuration: Double?
    var filterPreset: FilterPreset

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
    }

    var totalDuration: Double { segments.reduce(0) { $0 + $1.durationSeconds } }
    var hasSegments: Bool { !segments.isEmpty }
}
