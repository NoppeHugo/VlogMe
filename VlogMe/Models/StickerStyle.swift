import CoreGraphics

/// Position du sticker (date / lieu) sur l'image.
enum StickerPosition: String, Codable, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeading:     return "Haut g."
        case .topTrailing:    return "Haut d."
        case .bottomLeading:  return "Bas g."
        case .bottomTrailing: return "Bas d."
        }
    }

    /// Point d'ancrage normalisé (0–1) dans le repère « origine en haut à gauche ».
    var anchor: CGPoint {
        switch self {
        case .topLeading:     return CGPoint(x: 0, y: 0)
        case .topTrailing:    return CGPoint(x: 1, y: 0)
        case .bottomLeading:  return CGPoint(x: 0, y: 1)
        case .bottomTrailing: return CGPoint(x: 1, y: 1)
        }
    }

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }
}

/// Apparence du sticker.
enum StickerStyle: String, Codable, CaseIterable, Identifiable {
    case pill      // pastille blanche translucide, texte sombre
    case outline   // texte blanc + contour, fond transparent
    case accent    // pastille corail, texte noir

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pill:    return "Pastille"
        case .outline: return "Contour"
        case .accent:  return "Corail"
        }
    }
}
