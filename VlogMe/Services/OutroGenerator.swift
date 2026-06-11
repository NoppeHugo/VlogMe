import AVFoundation
import UIKit

enum OutroError: LocalizedError {
    case writerSetup
    case pixelBuffer

    var errorDescription: String? {
        switch self {
        case .writerSetup: return "Impossible de préparer l'outro."
        case .pixelBuffer: return "Impossible de générer l'image de l'outro."
        }
    }
}

/// Génère l'outro de marque « VlogMe » de 3 s ajoutée en gratuit (§3.1, §8).
///
/// Plutôt qu'un asset vidéo embarqué, on rend un clip noir avec le logo texte,
/// à la taille exacte de la composition (donc cohérent en 9:16 / 16:9 et 1080p / 4K).
/// Le résultat est mis en cache dans le dossier temporaire, par taille.
enum OutroGenerator {

    static func outro(renderSize: CGSize, duration: Double = 3.0) async throws -> URL {
        let name = "vlogme-outro-\(Int(renderSize.width))x\(Int(renderSize.height)).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try await render(to: url, size: renderSize, duration: duration)
        return url
    }

    private static func render(to url: URL, size: CGSize, duration: Double, fps: Int32 = 30) async throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else { throw OutroError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? OutroError.writerSetup }
        writer.startSession(atSourceTime: .zero)

        let image = brandImage(size: size)
        guard let cgImage = image.cgImage,
              let buffer = pixelBuffer(from: cgImage, size: size, pool: adaptor.pixelBufferPool) else {
            throw OutroError.pixelBuffer
        }

        let frameCount = Int(duration * Double(fps))
        var frame = 0
        let queue = DispatchQueue(label: "pro.vlogme.outro")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if frame >= frameCount {
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: writer.error ?? OutroError.writerSetup)
                            }
                        }
                        return
                    }
                    let time = CMTime(value: CMTimeValue(frame), timescale: fps)
                    if !adaptor.append(buffer, withPresentationTime: time) {
                        input.markAsFinished()
                        continuation.resume(throwing: writer.error ?? OutroError.pixelBuffer)
                        return
                    }
                    frame += 1
                }
            }
        }
    }

    // MARK: - Rendu graphique

    private static func brandImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let titleSize = min(size.width, size.height) * 0.10
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: titleSize, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let title = "VlogMe" as NSString
            let titleBounds = title.size(withAttributes: titleAttrs)
            let titleRect = CGRect(
                x: 0,
                y: (size.height - titleBounds.height) / 2 - titleBounds.height * 0.3,
                width: size.width,
                height: titleBounds.height
            )
            title.draw(in: titleRect, withAttributes: titleAttrs)

            let subSize = titleSize * 0.32
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: subSize, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7),
                .paragraphStyle: paragraph
            ]
            let sub = "Monté avec VlogMe" as NSString
            let subBounds = sub.size(withAttributes: subAttrs)
            let subRect = CGRect(
                x: 0,
                y: titleRect.maxY + subSize * 0.6,
                width: size.width,
                height: subBounds.height
            )
            sub.draw(in: subRect, withAttributes: subAttrs)
        }
    }

    private static func pixelBuffer(from image: CGImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let createAttrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        let status: CVReturn
        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        } else {
            status = CVPixelBufferCreate(
                nil, Int(size.width), Int(size.height),
                kCVPixelFormatType_32ARGB, createAttrs, &pixelBuffer
            )
        }
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
