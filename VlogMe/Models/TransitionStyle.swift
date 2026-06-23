import CoreGraphics

/// Transition appliquée entre les clips du vlog (idée signature).
///
/// Rendue par `VideoAssembler` via des rampes de transform et/ou de courts
/// flashs — aucune dépendance externe.
enum TransitionStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case flash    // bref flash blanc entre les clips
    case zoom     // « zoom punch » : léger zoom qui se pose en début de clip
    case whip     // glissé horizontal rapide (façon whip-pan)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:  return "Aucune"
        case .flash: return "Flash"
        case .zoom:  return "Zoom punch"
        case .whip:  return "Whip"
        }
    }

    /// Durée du flash blanc inséré entre les clips (0 si non pertinent).
    var flashDuration: Double { self == .flash ? 0.06 : 0 }

    /// Durée de la rampe de transform en début de clip (0 si non pertinent).
    var rampDuration: Double {
        switch self {
        case .zoom: return 0.22
        case .whip: return 0.12
        default:    return 0
        }
    }
}
