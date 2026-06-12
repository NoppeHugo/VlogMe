import AVFoundation
import Photos

enum ExportError: LocalizedError {
    case noSegments
    case cannotCreateSession
    case cancelled
    case photosDenied
    case unknown

    var errorDescription: String? {
        switch self {
        case .noSegments:          return "Aucun segment à exporter."
        case .cannotCreateSession: return "Impossible de préparer l'encodage."
        case .cancelled:           return "Export annulé."
        case .photosDenied:        return "Accès à Photos refusé. Autorise-le dans les Réglages."
        case .unknown:             return "Une erreur inattendue est survenue."
        }
    }
}

/// Encode la composition finale (+ filtre optionnel) en MP4.
struct Exporter {

    /// - Parameters:
    ///   - composition: la composition assemblée par `VideoAssembler`.
    ///   - videoComposition: les instructions de rendu (transforms, format).
    ///   - filterPreset: filtre vintage à appliquer en post-traitement (`.none` = pas de filtre).
    ///   - onProgress: progression de 0 à 1.
    static func export(
        composition: AVComposition,
        videoComposition: AVVideoComposition,
        filterPreset: FilterPreset = .none,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        // Fraction de progression réservée à la première passe
        let step1Fraction: Double = filterPreset == .none ? 1.0 : 0.62

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VlogMe-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: tempURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ExportError.cannotCreateSession }

        session.outputURL       = tempURL
        session.outputFileType  = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        let pollTask = Task {
            while !Task.isCancelled {
                onProgress(Double(session.progress) * step1Fraction)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { pollTask.cancel() }

        try await runSession(session)

        guard filterPreset != .none else {
            onProgress(1)
            return tempURL
        }

        // Deuxième passe : application du filtre CIImage
        let filteredURL = try await applyFilter(filterPreset, to: tempURL) { p in
            onProgress(step1Fraction + p * (1 - step1Fraction))
        }
        try? FileManager.default.removeItem(at: tempURL)
        onProgress(1)
        return filteredURL
    }

    // MARK: - Filtre (2e passe)

    private static func applyFilter(
        _ preset: FilterPreset,
        to url: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VlogMe-filtered-\(UUID().uuidString).mp4")

        let filterComposition = AVVideoComposition(asset: asset) { request in
            let output = preset.apply(to: request.sourceImage.clampedToExtent())
                .cropped(to: request.sourceImage.extent)
            request.finish(with: output, context: nil)
        }

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ExportError.cannotCreateSession }

        session.outputURL        = outputURL
        session.outputFileType   = .mp4
        session.videoComposition = filterComposition
        session.shouldOptimizeForNetworkUse = true

        let pollTask = Task {
            while !Task.isCancelled {
                onProgress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { pollTask.cancel() }

        try await runSession(session)
        return outputURL
    }

    // MARK: - Helper

    private static func runSession(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed: cont.resume()
                case .cancelled: cont.resume(throwing: ExportError.cancelled)
                case .failed:    cont.resume(throwing: session.error ?? ExportError.unknown)
                default:         cont.resume(throwing: ExportError.unknown)
                }
            }
        }
    }
}

/// Sauvegarde dans la pellicule (permission « ajout seul »).
enum PhotoSaver {

    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photosDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
