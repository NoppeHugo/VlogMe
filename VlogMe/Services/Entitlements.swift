import Foundation
import Combine

enum ExportResolution {
    case hd1080
    case uhd4K

    var scale: CGFloat {
        switch self {
        case .hd1080: return 1
        case .uhd4K:  return 2
        }
    }

    var label: String {
        switch self {
        case .hd1080: return "1080p"
        case .uhd4K:  return "4K"
        }
    }
}

/// Accès aux fonctionnalités — tout débloqué pour les tests.
/// Pour brancher RevenueCat plus tard : `isPro = customerInfo.entitlements["pro"]?.isActive ?? false`
@MainActor
final class Entitlements: ObservableObject {

    @Published var isPro: Bool = true

    var exportResolution: ExportResolution { isPro ? .uhd4K : .hd1080 }
    var includesOutro: Bool { false }
    var maxVlogDuration: Double? { nil }
}
