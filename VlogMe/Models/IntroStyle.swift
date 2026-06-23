import CoreGraphics

/// Style du carton d'intro « stylé » inséré au début du vlog (signature VlogMe).
///
/// `.none` signifie « pas d'intro ». Chaque autre cas correspond à une esthétique
/// rendue par `IntroGenerator`. Volontairement sans dépendance UIKit : le moteur
/// de rendu interprète le style, le modèle ne fait que le décrire.
enum IntroStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case minimal      // fond noir, gros titre blanc minuscule (cf. capture "vlog")
    case bold         // fond corail, titre noir ultra-gras
    case magazine     // fond crème, titre éditorial + sous-titre espacé
    case neon         // fond noir, titre blanc avec halo orange
    case handwritten  // fond sombre, titre script manuscrit

    var id: String { rawValue }

    /// Vrai si une intro doit être rendue (tout sauf `.none`).
    var isEnabled: Bool { self != .none }

    /// Libellé affiché dans le sélecteur.
    var label: String {
        switch self {
        case .none:        return "Aucune"
        case .minimal:     return "Minimal"
        case .bold:        return "Punch"
        case .magazine:    return "Magazine"
        case .neon:        return "Néon"
        case .handwritten: return "Manuscrit"
        }
    }

    /// Styles proposables à l'utilisateur (exclut `.none`, géré par un toggle).
    static var selectable: [IntroStyle] {
        allCases.filter { $0.isEnabled }
    }

    /// Durée par défaut de l'intro, en secondes.
    var defaultDuration: Double { 1.8 }
}
