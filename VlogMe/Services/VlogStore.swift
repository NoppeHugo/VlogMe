import Foundation
import Combine

/// La liste ordonnée des segments du vlog en cours + sa persistance (brouillons, §7).
///
/// Chaque segment est un vrai fichier `.mov` dans `Documents/segments/`.
/// Un index JSON (`vlog_index.json`) garde l'ordre, le format et les métadonnées.
/// À la réouverture de l'app, on recharge l'index → le vlog réapparaît intact.
@MainActor
final class VlogStore: ObservableObject {

    @Published private(set) var segments: [VideoSegment] = []
    @Published var aspectRatio: AspectRatio = .vertical {
        didSet { save() }
    }

    let segmentsDirectory: URL
    private let indexURL: URL

    var totalDuration: Double { segments.reduce(0) { $0 + $1.durationSeconds } }
    var hasSegments: Bool { !segments.isEmpty }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        segmentsDirectory = documents.appendingPathComponent("segments", isDirectory: true)
        indexURL = documents.appendingPathComponent("vlog_index.json")
        try? FileManager.default.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - URLs

    /// Résout le chemin absolu d'un segment au moment de l'exécution.
    func url(for segment: VideoSegment) -> URL {
        segmentsDirectory.appendingPathComponent(segment.fileName)
    }

    /// Une URL de fichier neuve et unique pour enregistrer le prochain segment.
    func newSegmentURL() -> URL {
        segmentsDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    }

    // MARK: - Mutations

    func append(_ segment: VideoSegment) {
        segments.append(segment)
        save()
    }

    /// Supprime le dernier segment (utilisé par « Refaire » et « Supprimer », §4).
    func removeLast() {
        guard let last = segments.last else { return }
        delete(last)
    }

    func delete(_ segment: VideoSegment) {
        try? FileManager.default.removeItem(at: url(for: segment))
        segments.removeAll { $0.id == segment.id }
        save()
    }

    /// Nettoyage complet (vlog exporté ou abandonné) — évite de saturer le stockage (§5, §11).
    func clear() {
        for segment in segments {
            try? FileManager.default.removeItem(at: url(for: segment))
        }
        segments.removeAll()
        save()
    }

    // MARK: - Persistance

    private struct Index: Codable {
        var aspectRatio: AspectRatio
        var segments: [VideoSegment]
    }

    private func save() {
        let index = Index(aspectRatio: aspectRatio, segments: segments)
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("[VlogStore] échec de sauvegarde de l'index : \(error)")
        }
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: indexURL),
            let index = try? JSONDecoder().decode(Index.self, from: data)
        else { return }

        aspectRatio = index.aspectRatio
        // Défensif : on écarte les segments dont le fichier a disparu.
        let survivors = index.segments.filter {
            FileManager.default.fileExists(atPath: segmentsDirectory.appendingPathComponent($0.fileName).path)
        }
        segments = survivors
        if survivors.count != index.segments.count { save() }
    }
}
