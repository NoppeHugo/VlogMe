import UIKit
import AVFoundation

/// Filigrane « VlogMe » incrusté sur toute la vidéo à l'export pour les utilisateurs
/// gratuits. Passer à Pro le retire. Incrusté via `AVVideoCompositionCoreAnimationTool`
/// comme le sticker et les cartons de ville.
enum WatermarkRenderer {

    /// Calque parent (taille de rendu) avec le filigrane en bas au centre.
    static func makeLayer(renderSize: CGSize) -> CALayer? {
        guard let image = watermarkImage(targetWidth: renderSize.width) else { return nil }

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.isGeometryFlipped = false

        let sub = CALayer()
        let w = image.size.width
        let h = image.size.height
        // Repère Core Animation : origine en bas à gauche → y faible = bas de l'écran.
        sub.frame = CGRect(
            x: (renderSize.width - w) / 2,
            y: renderSize.height * 0.055,
            width: w,
            height: h
        )
        sub.contents = image.cgImage
        sub.contentsScale = 1
        sub.opacity = 0.9
        parent.addSublayer(sub)
        return parent
    }

    /// Rendu bitmap du filigrane : petit losange d'accent + « VlogMe », ombre douce
    /// pour rester lisible sur n'importe quel fond.
    static func watermarkImage(targetWidth: CGFloat) -> UIImage? {
        let fontSize = max(18, targetWidth * 0.040)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let text = "VlogMe" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .kern: fontSize * 0.02
        ]
        let textSize = text.size(withAttributes: attrs)

        let diamond = fontSize * 0.5
        let gap = fontSize * 0.4
        let padH = fontSize * 0.5
        let padV = fontSize * 0.4
        let size = CGSize(
            width: ceil(diamond + gap + textSize.width + padH * 2),
            height: ceil(max(textSize.height, diamond) + padV * 2)
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 6,
                         color: UIColor.black.withAlphaComponent(0.5).cgColor)

            // Losange d'accent (orange VlogMe)
            let cx = padH + diamond / 2
            let cy = size.height / 2
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cx, y: cy - diamond / 2))
            path.addLine(to: CGPoint(x: cx + diamond / 2, y: cy))
            path.addLine(to: CGPoint(x: cx, y: cy + diamond / 2))
            path.addLine(to: CGPoint(x: cx - diamond / 2, y: cy))
            path.close()
            UIColor(red: 1, green: 0.42, blue: 0.29, alpha: 0.95).setFill()
            path.fill()

            text.draw(
                at: CGPoint(x: padH + diamond + gap, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }
}
