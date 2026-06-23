import UIKit
import AVFoundation

/// Sticker « date / lieu » incrusté sur tout le vlog (idée signature).
///
/// À l'export, on incruste un `CALayer` via `AVVideoCompositionCoreAnimationTool`
/// (le repère Core Animation a son origine en bas à gauche). En prévisualisation,
/// l'incrustation `AVVideoCompositionCoreAnimationTool` n'étant pas appliquée par
/// `AVPlayer`, on superpose à la place `StickerOverlayView` (SwiftUI).
enum StickerRenderer {

    /// Construit le texte affiché (date optionnelle + texte libre).
    static func displayText(text: String, showDate: Bool, date: Date) -> String {
        var parts: [String] = []
        if showDate {
            let f = DateFormatter()
            f.dateFormat = "d MMM"
            f.locale = Locale(identifier: "fr_FR")
            parts.append(f.string(from: date))
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.joined(separator: "  ·  ")
    }

    /// Calque parent (taille de rendu) prêt pour `AVVideoCompositionCoreAnimationTool`.
    static func makeLayer(
        text: String,
        renderSize: CGSize,
        position: StickerPosition,
        style: StickerStyle
    ) -> CALayer? {
        guard !text.isEmpty,
              let image = stickerImage(text: text, style: style, targetWidth: renderSize.width) else { return nil }

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.isGeometryFlipped = false

        let sub = CALayer()
        let margin = renderSize.width * 0.045
        let w = image.size.width
        let h = image.size.height
        let x = position.isLeading ? margin : renderSize.width - margin - w
        // Repère Core Animation : y vers le haut → « top » = y élevé.
        let y = position.isTop ? renderSize.height - margin - h : margin
        sub.frame = CGRect(x: x, y: y, width: w, height: h)
        sub.contents = image.cgImage
        sub.contentsScale = 1
        parent.addSublayer(sub)
        return parent
    }

    /// Rendu bitmap du sticker (pastille + texte), partagé pour garder un look stable.
    static func stickerImage(text: String, style: StickerStyle, targetWidth: CGFloat) -> UIImage? {
        guard !text.isEmpty else { return nil }

        let fontSize = max(16, targetWidth * 0.034)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let padH = fontSize * 0.85
        let padV = fontSize * 0.5

        let textColor: UIColor
        let fillColor: UIColor
        var strokeColor: UIColor? = nil
        switch style {
        case .pill:
            textColor = UIColor(white: 0.1, alpha: 1)
            fillColor = UIColor(white: 1, alpha: 0.85)
        case .outline:
            textColor = .white
            fillColor = .clear
            strokeColor = UIColor(white: 1, alpha: 0.9)
        case .accent:
            textColor = .black
            fillColor = UIColor(red: 1, green: 0.42, blue: 0.29, alpha: 0.95)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let size = CGSize(width: ceil(textSize.width + padH * 2),
                          height: ceil(textSize.height + padV * 2))
        let radius = size.height / 2

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            if fillColor != .clear {
                fillColor.setFill()
                path.fill()
            }
            if let strokeColor {
                strokeColor.setStroke()
                path.lineWidth = max(1.5, fontSize * 0.06)
                path.stroke()
            }
            (text as NSString).draw(
                at: CGPoint(x: padH, y: padV),
                withAttributes: attrs
            )
        }
    }
}
