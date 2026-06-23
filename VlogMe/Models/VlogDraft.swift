import Foundation

struct VlogDraft: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var segments: [VideoSegment]
    var aspectRatio: AspectRatio
    var targetDuration: Double?
    var filterPreset: FilterPreset
    var maxSegmentDuration: Double?      // Auto-coupe après X sec (nil = infini)
    var backgroundMusicPath: String?     // Chemin relatif au dossier du draft
    var backgroundMusicVolume: Float     // 0.0 – 1.0

    // MARK: - Intro stylée (signature VlogMe)
    var introStyle: IntroStyle           // .none = pas d'intro
    var introText: String                // titre affiché (ex: "vlog")
    var introSubtitle: String            // sous-titre (ex: "day in my life")

    // MARK: - Hook montage (tendance TikTok : clips qui s'enchaînent)
    var hookEnabled: Bool                // aperçu rapide des clips au début
    var hookGap: Double                  // pause entre chaque clip (0.1 – 0.2 s)

    init(name: String = "") {
        id = UUID()
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_FR")
        self.name = name.isEmpty ? "Vlog du \(f.string(from: Date()))" : name
        createdAt = Date()
        segments = []
        aspectRatio = .vertical
        targetDuration = nil
        filterPreset = .none
        maxSegmentDuration = nil
        backgroundMusicPath = nil
        backgroundMusicVolume = 0.3
        // Intro activée par défaut sur les nouveaux vlogs → effet signature immédiat.
        introStyle = .minimal
        introText = "vlog"
        introSubtitle = ""
        hookEnabled = false
        hookGap = 0.15
    }

    // MARK: - Decodable rétro-compatible
    //
    // Les anciens brouillons (sur l'appareil de l'utilisateur) ne contiennent pas
    // les nouvelles clés. On décode chaque nouveau champ avec un repli pour ne
    // jamais casser un brouillon existant (principe « zéro perte de données »).

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, segments, aspectRatio, targetDuration, filterPreset
        case maxSegmentDuration, backgroundMusicPath, backgroundMusicVolume
        case introStyle, introText, introSubtitle, hookEnabled, hookGap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decode(UUID.self, forKey: .id)
        name                  = try c.decode(String.self, forKey: .name)
        createdAt             = try c.decode(Date.self, forKey: .createdAt)
        segments              = try c.decode([VideoSegment].self, forKey: .segments)
        aspectRatio           = try c.decode(AspectRatio.self, forKey: .aspectRatio)
        targetDuration        = try c.decodeIfPresent(Double.self, forKey: .targetDuration)
        filterPreset          = try c.decodeIfPresent(FilterPreset.self, forKey: .filterPreset) ?? .none
        maxSegmentDuration    = try c.decodeIfPresent(Double.self, forKey: .maxSegmentDuration)
        backgroundMusicPath   = try c.decodeIfPresent(String.self, forKey: .backgroundMusicPath)
        backgroundMusicVolume = try c.decodeIfPresent(Float.self, forKey: .backgroundMusicVolume) ?? 0.3
        // Repli `.none` : les vlogs déjà créés gardent leur rendu d'origine.
        introStyle            = try c.decodeIfPresent(IntroStyle.self, forKey: .introStyle) ?? .none
        introText             = try c.decodeIfPresent(String.self, forKey: .introText) ?? ""
        introSubtitle         = try c.decodeIfPresent(String.self, forKey: .introSubtitle) ?? ""
        hookEnabled           = try c.decodeIfPresent(Bool.self, forKey: .hookEnabled) ?? false
        hookGap               = try c.decodeIfPresent(Double.self, forKey: .hookGap) ?? 0.15
    }

    var totalDuration: Double { segments.reduce(0) { $0 + $1.effectiveDuration } }
    var hasSegments: Bool { !segments.isEmpty }
}
