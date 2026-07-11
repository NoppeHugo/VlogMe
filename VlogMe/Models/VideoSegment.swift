import Foundation

struct VideoSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let durationSeconds: Double
    let facing: CameraFacing
    let createdAt: Date
    /// Instant précis (à la milliseconde) du début d'enregistrement.
    /// Sert à remettre les clips de tous les participants dans l'ordre
    /// chronologique réel dans un vlog partagé. `nil` sur les anciens segments.
    let capturedAt: Date?
    /// Identifiant CloudKit de l'auteur du segment. `nil` = filmé sur cet appareil.
    let authorID: String?
    /// Nom d'affichage de l'auteur (participant d'un vlog partagé).
    let authorName: String?
    /// Ville où le clip a été filmé (ex. « Bruxelles »), pour les cartons de
    /// changement de ville à l'export. `nil` si localisation indisponible.
    let city: String?
    // Trim (nil = pas de trim appliqué)
    var trimStart: Double?
    var trimEnd: Double?

    init(
        id: UUID = UUID(),
        fileName: String,
        durationSeconds: Double,
        facing: CameraFacing,
        createdAt: Date = .now,
        capturedAt: Date? = nil,
        authorID: String? = nil,
        authorName: String? = nil,
        city: String? = nil,
        trimStart: Double? = nil,
        trimEnd: Double? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.facing = facing
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.authorID = authorID
        self.authorName = authorName
        self.city = city
        self.trimStart = trimStart
        self.trimEnd = trimEnd
    }

    // MARK: - Decodable rétro-compatible
    //
    // Les segments déjà sur disque ne contiennent pas les clés collaboratives ;
    // on les décode avec un repli pour ne jamais casser un brouillon existant.

    enum CodingKeys: String, CodingKey {
        case id, fileName, durationSeconds, facing, createdAt
        case capturedAt, authorID, authorName, city
        case trimStart, trimEnd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        fileName        = try c.decode(String.self, forKey: .fileName)
        durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        facing          = try c.decode(CameraFacing.self, forKey: .facing)
        createdAt       = try c.decode(Date.self, forKey: .createdAt)
        capturedAt      = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
        authorID        = try c.decodeIfPresent(String.self, forKey: .authorID)
        authorName      = try c.decodeIfPresent(String.self, forKey: .authorName)
        city            = try c.decodeIfPresent(String.self, forKey: .city)
        trimStart       = try c.decodeIfPresent(Double.self, forKey: .trimStart)
        trimEnd         = try c.decodeIfPresent(Double.self, forKey: .trimEnd)
    }

    var effectiveDuration: Double {
        let s = trimStart ?? 0
        let e = trimEnd ?? durationSeconds
        return max(0, e - s)
    }

    /// Date de référence pour l'ordre chronologique d'un vlog partagé.
    var sortDate: Date { capturedAt ?? createdAt }

    /// Segment filmé sur cet appareil (par opposition à un segment reçu d'un participant).
    var isMine: Bool { authorID == nil }
}
