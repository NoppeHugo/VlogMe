import Foundation

/// Un clip filmé, déjà écrit sur le disque (cf. §7 — zéro perte de données).
///
/// IMPORTANT : on ne stocke qu'un `fileName` RELATIF au dossier des segments,
/// jamais une URL absolue. Le chemin du conteneur de l'app iOS change entre
/// les lancements ; un chemin absolu persisté deviendrait invalide.
struct VideoSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let durationSeconds: Double
    let facing: CameraFacing
    let createdAt: Date

    init(
        id: UUID = UUID(),
        fileName: String,
        durationSeconds: Double,
        facing: CameraFacing,
        createdAt: Date = .now
    ) {
        self.id = id
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.facing = facing
        self.createdAt = createdAt
    }
}
