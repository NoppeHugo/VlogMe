import Foundation

struct VideoSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let durationSeconds: Double
    let facing: CameraFacing
    let createdAt: Date
    // Trim (nil = pas de trim appliqué)
    var trimStart: Double?
    var trimEnd: Double?

    init(
        id: UUID = UUID(),
        fileName: String,
        durationSeconds: Double,
        facing: CameraFacing,
        createdAt: Date = .now,
        trimStart: Double? = nil,
        trimEnd: Double? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.facing = facing
        self.createdAt = createdAt
        self.trimStart = trimStart
        self.trimEnd = trimEnd
    }

    var effectiveDuration: Double {
        let s = trimStart ?? 0
        let e = trimEnd ?? durationSeconds
        return max(0, e - s)
    }
}
