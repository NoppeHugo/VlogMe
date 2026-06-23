import Foundation

/// Un « template de vlog » : un pack cohérent qui règle en un tap l'intro, le
/// filtre, le hook, les transitions et le beat-sync. C'est le raccourci
/// « monté comme un pro sans réfléchir » (idée signature).
struct VlogTemplate: Identifiable {
    let id: String
    let emoji: String
    let name: String

    let introStyle: IntroStyle
    let introSubtitle: String
    let filter: FilterPreset
    let transition: TransitionStyle
    let hookEnabled: Bool
    let hookGap: Double
    let beatSync: Bool

    /// Catalogue proposé à l'utilisateur.
    static let all: [VlogTemplate] = [
        VlogTemplate(
            id: "morning", emoji: "☕️", name: "Morning routine",
            introStyle: .minimal, introSubtitle: "day in my life",
            filter: .warm, transition: .zoom,
            hookEnabled: true, hookGap: 0.12, beatSync: false
        ),
        VlogTemplate(
            id: "aesthetic", emoji: "🍵", name: "Aesthetic / café",
            introStyle: .magazine, introSubtitle: "cafe hopping",
            filter: .faded, transition: .none,
            hookEnabled: true, hookGap: 0.18, beatSync: false
        ),
        VlogTemplate(
            id: "travel", emoji: "✈️", name: "Travel",
            introStyle: .bold, introSubtitle: "travel diary",
            filter: .retro, transition: .whip,
            hookEnabled: true, hookGap: 0.1, beatSync: true
        ),
        VlogTemplate(
            id: "party", emoji: "🎉", name: "Night out",
            introStyle: .neon, introSubtitle: "the weekend",
            filter: .grain, transition: .flash,
            hookEnabled: true, hookGap: 0.1, beatSync: true
        ),
        VlogTemplate(
            id: "diary", emoji: "📖", name: "Journal calme",
            introStyle: .handwritten, introSubtitle: "",
            filter: .cold, transition: .none,
            hookEnabled: false, hookGap: 0.15, beatSync: false
        )
    ]
}
