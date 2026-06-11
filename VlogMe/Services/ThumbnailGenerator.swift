import AVFoundation
import UIKit

/// Génère une miniature pour la pile de segments (cf. §4, Phase 2).
enum ThumbnailGenerator {

    static func thumbnail(for url: URL, maxSize: CGFloat = 240) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true   // respecte l'orientation
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)

        let time = CMTime(seconds: 0.05, preferredTimescale: 600)
        do {
            let cgImage = try await generator.image(at: time).image
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
