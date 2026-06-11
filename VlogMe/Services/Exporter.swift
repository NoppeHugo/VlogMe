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

/// Encode la composition finale et l'écrit sur le disque (cf. §4, écran 3 ; Phase 4).
struct Exporter {

    /// Encode `composition` (+ `videoComposition`) en MP4 et remonte la progression (0→1).
    static func export(
        composition: AVComposition,
        videoComposition: AVVideoComposition,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VlogMe-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ExportError.cannotCreateSession }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        // Suivi de progression : on échantillonne `session.progress` pendant l'encodage.
        let pollTask = Task {
            while !Task.isCancelled {
                onProgress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 100_000_000) // 0,1 s
            }
        }
        defer { pollTask.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: ExportError.cancelled)
                case .failed:
                    continuation.resume(throwing: session.error ?? ExportError.unknown)
                default:
                    continuation.resume(throwing: ExportError.unknown)
                }
            }
        }

        onProgress(1)
        return outputURL
    }
}

/// Sauvegarde dans la pellicule via la permission « ajout seul » (cf. §6.2/§6.4).
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
