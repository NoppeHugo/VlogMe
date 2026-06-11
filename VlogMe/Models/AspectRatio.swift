import CoreGraphics

/// Le format de sortie du vlog. Le vertical 9:16 est le défaut (cf. cahier des charges §4).
enum AspectRatio: String, Codable, CaseIterable, Identifiable {
    case vertical    // 9:16
    case horizontal  // 16:9

    var id: String { rawValue }

    /// Dimension de rendu de base (1080p) de la composition finale, en pixels.
    var renderSize: CGSize {
        switch self {
        case .vertical:   return CGSize(width: 1080, height: 1920)
        case .horizontal: return CGSize(width: 1920, height: 1080)
        }
    }

    /// Dimension de rendu mise à l'échelle selon la résolution d'export (1080p / 4K).
    func renderSize(scale: CGFloat) -> CGSize {
        CGSize(width: renderSize.width * scale, height: renderSize.height * scale)
    }

    /// Libellé affiché sur le bouton de bascule.
    var label: String {
        switch self {
        case .vertical:   return "9:16"
        case .horizontal: return "16:9"
        }
    }

    mutating func toggle() {
        self = (self == .vertical) ? .horizontal : .vertical
    }
}
