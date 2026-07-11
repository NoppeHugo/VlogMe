import UIKit
import AVFoundation

/// Carton « changement de ville » : quand le vlog passe d'une ville à une autre,
/// le nom de la nouvelle ville s'affiche 3 s en surimpression stylée (fondu +
/// légère montée) au début du premier clip filmé là-bas.
///
/// Incrusté à l'export via `AVVideoCompositionCoreAnimationTool`, comme le sticker.
enum CityCardRenderer {

    /// Durée d'affichage d'un carton.
    static let displayDuration: Double = 3.0

    struct Marker: Equatable {
        let time: Double     // début d'affichage, en secondes dans la composition
        let city: String
    }

    /// Détecte les changements de ville dans l'ordre du montage.
    ///
    /// Un carton par changement, y compris la toute première ville — mais
    /// uniquement si le vlog traverse au moins deux villes différentes
    /// (un vlog entier dans la même ville n'affiche rien).
    /// Les clips sans ville (localisation refusée, ancien clip) sont ignorés
    /// sans casser la chaîne.
    static func markers(cityStarts: [(city: String?, start: Double)]) -> [Marker] {
        var result: [Marker] = []
        var lastCity: String?
        for entry in cityStarts {
            guard let city = entry.city?.trimmingCharacters(in: .whitespaces), !city.isEmpty else { continue }
            if city != lastCity {
                result.append(Marker(time: entry.start, city: city))
                lastCity = city
            }
        }
        let distinctCities = Set(result.map { $0.city })
        return distinctCities.count >= 2 ? result : []
    }

    /// Calque parent (taille de rendu) contenant tous les cartons, chacun animé
    /// sur la timeline de la vidéo (apparition à `marker.time`, 3 s, disparition).
    static func makeLayer(markers: [Marker], renderSize: CGSize) -> CALayer? {
        guard !markers.isEmpty else { return nil }

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.isGeometryFlipped = false

        for marker in markers {
            guard let image = cardImage(city: marker.city, targetWidth: renderSize.width) else { continue }

            let card = CALayer()
            let w = image.size.width
            let h = image.size.height
            // Centré horizontalement, dans le tiers bas (zone classique des titres).
            card.frame = CGRect(
                x: (renderSize.width - w) / 2,
                y: renderSize.height * 0.24,
                width: w,
                height: h
            )
            card.contents = image.cgImage
            card.contentsScale = 1
            card.opacity = 0

            // La timeline vidéo démarre à AVCoreAnimationBeginTimeAtZero
            // (beginTime 0 signifierait « maintenant » pour Core Animation).
            let begin = AVCoreAnimationBeginTimeAtZero + max(marker.time, 0)

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values   = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.12, 0.85, 1]
            fade.duration = displayDuration
            fade.beginTime = begin
            fade.isRemovedOnCompletion = false
            fade.fillMode = .both
            card.add(fade, forKey: "cityFade")

            // Lente montée pendant l'affichage (effet titre de film).
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = -renderSize.height * 0.012
            rise.toValue   = renderSize.height * 0.012
            rise.duration  = displayDuration
            rise.beginTime = begin
            rise.isRemovedOnCompletion = false
            rise.fillMode = .both
            card.add(rise, forKey: "cityRise")

            parent.addSublayer(card)
        }

        return parent.sublayers?.isEmpty == false ? parent : nil
    }

    /// Rendu bitmap du carton : nom de ville en capitales espacées, encadré de
    /// deux traits fins, avec une ombre portée douce pour rester lisible partout.
    static func cardImage(city: String, targetWidth: CGFloat) -> UIImage? {
        let name = city.uppercased()
        guard !name.isEmpty else { return nil }

        let fontSize = max(28, targetWidth * 0.072)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: fontSize * 0.18
        ]
        let textSize = (name as NSString).size(withAttributes: attrs)

        let lineSpacing = fontSize * 0.45
        let lineWidth = min(textSize.width * 0.6, targetWidth * 0.3)
        let padding = fontSize * 0.6
        let size = CGSize(
            width: ceil(min(textSize.width + padding * 2, targetWidth * 0.94)),
            height: ceil(textSize.height + (lineSpacing + 2) * 2)
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 12,
                         color: UIColor.black.withAlphaComponent(0.55).cgColor)

            // Traits fins au-dessus et en dessous du nom.
            cg.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            let lineX = (size.width - lineWidth) / 2
            cg.fill(CGRect(x: lineX, y: 0.5, width: lineWidth, height: 2))
            cg.fill(CGRect(x: lineX, y: size.height - 2.5, width: lineWidth, height: 2))

            // Le kern ajoute un espace après la dernière lettre : on recentre.
            let kernOverflow = fontSize * 0.18 / 2
            (name as NSString).draw(
                at: CGPoint(x: (size.width - textSize.width) / 2 + kernOverflow,
                            y: lineSpacing + 2),
                withAttributes: attrs
            )
        }
    }
}
