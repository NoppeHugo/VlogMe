import AVFoundation
import UIKit

enum IntroError: LocalizedError {
    case writerSetup
    case pixelBuffer

    var errorDescription: String? {
        switch self {
        case .writerSetup: return "Impossible de préparer l'intro."
        case .pixelBuffer: return "Impossible de générer l'image de l'intro."
        }
    }
}

/// Génère le carton d'intro « stylé » inséré au début du vlog (signature VlogMe).
///
/// Contrairement à l'outro (image fixe), l'intro est **animée** : le titre apparaît
/// en fondu + léger zoom, le sous-titre glisse, un trait d'accent se déploie. On rend
/// donc une image par frame via `AVAssetWriter`, à la taille exacte de la composition.
/// Le résultat est mis en cache (clé = style + textes + marque + taille).
enum IntroGenerator {

    struct Spec {
        var style: IntroStyle
        var title: String
        var subtitle: String
        var branded: Bool          // ajoute le filigrane « VlogMe » (utilisateurs gratuits)
        var renderSize: CGSize
        var duration: Double
    }

    // MARK: - API

    static func intro(
        style: IntroStyle,
        title: String,
        subtitle: String,
        branded: Bool,
        renderSize: CGSize,
        duration: Double? = nil
    ) async throws -> URL {
        let spec = Spec(
            style: style,
            title: title.isEmpty ? "vlog" : title,
            subtitle: subtitle,
            branded: branded,
            renderSize: renderSize,
            duration: duration ?? style.defaultDuration
        )

        let key = "\(style.rawValue)-\(spec.title)-\(spec.subtitle)-\(branded ? "b" : "n")-\(Int(renderSize.width))x\(Int(renderSize.height))"
        let name = "vlogme-intro-\(stableHash(key)).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try await render(spec, to: url)
        return url
    }

    // MARK: - Rendu vidéo

    private static func render(_ spec: Spec, to url: URL, fps: Int32 = 30) async throws {
        try? FileManager.default.removeItem(at: url)
        let size = spec.renderSize

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

        guard writer.canAdd(input) else { throw IntroError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? IntroError.writerSetup }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(spec.duration * Double(fps)))
        var frame = 0
        let queue = DispatchQueue(label: "pro.vlogme.intro")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if frame >= frameCount {
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: writer.error ?? IntroError.writerSetup)
                            }
                        }
                        return
                    }
                    let t = Double(frame) / Double(frameCount - 1 == 0 ? 1 : frameCount - 1)
                    let image = frameImage(spec, t: t)
                    guard let cg = image.cgImage,
                          let buffer = pixelBuffer(from: cg, size: size, pool: adaptor.pixelBufferPool) else {
                        input.markAsFinished()
                        continuation.resume(throwing: IntroError.pixelBuffer)
                        return
                    }
                    let time = CMTime(value: CMTimeValue(frame), timescale: fps)
                    if !adaptor.append(buffer, withPresentationTime: time) {
                        input.markAsFinished()
                        continuation.resume(throwing: writer.error ?? IntroError.pixelBuffer)
                        return
                    }
                    frame += 1
                }
            }
        }
    }

    // MARK: - Composition d'une frame

    /// `t` ∈ [0, 1] : progression dans l'intro.
    private static func frameImage(_ spec: Spec, t: Double) -> UIImage {
        let size = spec.renderSize
        let palette = Palette(style: spec.style)

        // Courbes d'animation
        let titleIn  = easeOut(clamp((t - 0.02) / 0.30))   // titre : fondu + zoom au début
        let subIn    = easeOut(clamp((t - 0.22) / 0.30))   // sous-titre : légèrement décalé
        let lineIn   = easeOut(clamp((t - 0.12) / 0.40))   // trait d'accent : déploiement
        let fadeOut  = clamp((t - 0.86) / 0.14)            // sortie en fondu
        let globalAlpha = CGFloat(1.0 - fadeOut)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Fond
            palette.background.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            if let grad = palette.gradient {
                drawVerticalGradient(cg, colors: grad, size: size)
            }

            let minSide = min(size.width, size.height)
            let center  = CGPoint(x: size.width / 2, y: size.height / 2)

            // Trait d'accent (au-dessus du titre)
            let lineWidth = minSide * 0.34 * CGFloat(lineIn)
            if lineWidth > 1 {
                let lineRect = CGRect(
                    x: center.x - lineWidth / 2,
                    y: center.y - minSide * 0.20,
                    width: lineWidth,
                    height: max(2, minSide * 0.010)
                )
                palette.accent.withAlphaComponent(globalAlpha).setFill()
                UIBezierPath(roundedRect: lineRect, cornerRadius: lineRect.height / 2).fill()
            }

            // Titre
            let titleSize = minSide * palette.titleScale
            let titleFont = palette.titleFont(size: titleSize)
            let title = palette.uppercaseTitle ? spec.title.uppercased() : spec.title
            let titleAttrs = textAttributes(
                font: titleFont,
                color: palette.titleColor.withAlphaComponent(CGFloat(titleIn) * globalAlpha),
                tracking: palette.titleTracking
            )
            let titleBounds = (title as NSString).size(withAttributes: titleAttrs)
            let titleY = center.y - titleBounds.height / 2
            // Léger zoom d'entrée
            let scale = 0.92 + 0.08 * CGFloat(titleIn)
            cg.saveGState()
            cg.translateBy(x: center.x, y: titleY + titleBounds.height / 2)
            cg.scaleBy(x: scale, y: scale)
            if palette.glow {
                cg.setShadow(offset: .zero, blur: titleSize * 0.18,
                             color: palette.accent.withAlphaComponent(0.85 * globalAlpha).cgColor)
            }
            (title as NSString).draw(
                at: CGPoint(x: -titleBounds.width / 2, y: -titleBounds.height / 2),
                withAttributes: titleAttrs
            )
            cg.restoreGState()

            // Sous-titre
            let sub = palette.uppercaseSubtitle ? spec.subtitle.uppercased() : spec.subtitle
            if !sub.isEmpty {
                let subSize = titleSize * 0.20
                let subAttrs = textAttributes(
                    font: palette.subtitleFont(size: subSize),
                    color: palette.subtitleColor.withAlphaComponent(CGFloat(subIn) * globalAlpha),
                    tracking: palette.subtitleTracking
                )
                let subBounds = (sub as NSString).size(withAttributes: subAttrs)
                let subOffset = (1 - CGFloat(subIn)) * minSide * 0.03   // glisse vers le haut
                let subRect = CGRect(
                    x: (size.width - subBounds.width) / 2,
                    y: titleY + titleBounds.height + minSide * 0.04 + subOffset,
                    width: subBounds.width,
                    height: subBounds.height
                )
                (sub as NSString).draw(in: subRect, withAttributes: subAttrs)
            }

            // Filigrane de marque (gratuit)
            if spec.branded {
                let markSize = minSide * 0.030
                let markAttrs = textAttributes(
                    font: UIFont.systemFont(ofSize: markSize, weight: .semibold),
                    color: palette.titleColor.withAlphaComponent(0.55 * globalAlpha),
                    tracking: 1.5
                )
                let mark = "VlogMe" as NSString
                let markBounds = mark.size(withAttributes: markAttrs)
                mark.draw(
                    at: CGPoint(x: (size.width - markBounds.width) / 2,
                                y: size.height - markBounds.height - minSide * 0.05),
                    withAttributes: markAttrs
                )
            }
        }
    }

    // MARK: - Palette par style

    private struct Palette {
        var background: UIColor
        var gradient: [UIColor]?
        var accent: UIColor
        var titleColor: UIColor
        var subtitleColor: UIColor
        var titleScale: CGFloat
        var titleTracking: CGFloat
        var subtitleTracking: CGFloat
        var uppercaseTitle: Bool
        var uppercaseSubtitle: Bool
        var glow: Bool
        var titleFontName: String?
        var titleWeight: UIFont.Weight
        var subtitleWeight: UIFont.Weight

        init(style: IntroStyle) {
            // Valeurs par défaut (minimal)
            background = .black
            gradient = nil
            accent = UIColor(hex: 0xFF6B4A)
            titleColor = .white
            subtitleColor = UIColor.white.withAlphaComponent(0.75)
            titleScale = 0.16
            titleTracking = 0
            subtitleTracking = 2
            uppercaseTitle = false
            uppercaseSubtitle = false
            glow = false
            titleFontName = nil
            titleWeight = .heavy
            subtitleWeight = .medium

            switch style {
            case .none, .minimal:
                break
            case .bold:
                background = UIColor(hex: 0xFF6B4A)
                accent = .black
                titleColor = .black
                subtitleColor = UIColor.black.withAlphaComponent(0.7)
                titleScale = 0.18
                titleWeight = .black
                uppercaseTitle = true
                titleTracking = -1
                subtitleTracking = 4
                uppercaseSubtitle = true
            case .magazine:
                background = UIColor(hex: 0xF9F6F2)
                accent = UIColor(hex: 0x1A1A1A)
                titleColor = UIColor(hex: 0x1A1A1A)
                subtitleColor = UIColor(hex: 0x6B7280)
                titleScale = 0.15
                titleFontName = "Georgia-Bold"
                titleWeight = .bold
                subtitleTracking = 6
                uppercaseSubtitle = true
                subtitleWeight = .semibold
            case .neon:
                background = .black
                gradient = [UIColor(hex: 0x140B08), .black]
                accent = UIColor(hex: 0xFF6B4A)
                titleColor = .white
                glow = true
                titleScale = 0.17
                titleWeight = .black
                uppercaseTitle = true
                titleTracking = 1
            case .handwritten:
                background = UIColor(hex: 0x14110F)
                accent = UIColor(hex: 0xFF6B4A)
                titleColor = .white
                subtitleColor = UIColor.white.withAlphaComponent(0.7)
                titleScale = 0.19
                titleFontName = "SnellRoundhand-Bold"
                subtitleTracking = 3
            }
        }

        func titleFont(size: CGFloat) -> UIFont {
            if let name = titleFontName, let f = UIFont(name: name, size: size) { return f }
            return UIFont.systemFont(ofSize: size, weight: titleWeight)
        }

        func subtitleFont(size: CGFloat) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: subtitleWeight)
        }
    }

    // MARK: - Helpers dessin

    private static func textAttributes(font: UIFont, color: UIColor, tracking: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph
        ]
    }

    private static func drawVerticalGradient(_ cg: CGContext, colors: [UIColor], size: CGSize) {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: colors.map { $0.cgColor } as CFArray,
            locations: [0, 1]
        ) else { return }
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: size.width / 2, y: 0),
            end: CGPoint(x: size.width / 2, y: size.height),
            options: []
        )
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    private static func stableHash(_ s: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 36)
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

// MARK: - Couleur depuis un entier hexadécimal

private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
