import AppIntents
import Foundation

/// Mémorise une demande d'enregistrement reçue avant que la caméra ne soit montée
/// (lancement à froid via le widget, l'App Intent ou le bouton Action).
final class LaunchRouter {
    static let shared = LaunchRouter()
    private init() {}

    private var pendingRecord = false

    func setPendingRecord() { pendingRecord = true }

    /// Renvoie `true` une seule fois si une demande est en attente, puis la consomme.
    func consumePendingRecord() -> Bool {
        defer { pendingRecord = false }
        return pendingRecord
    }
}

/// Action « Filmer un vlog » exposée au système : utilisable depuis le bouton Action,
/// l'app Raccourcis, le Back Tap ou Siri. Ouvre VlogMe et lance l'enregistrement.
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Filmer un vlog"
    static var description = IntentDescription("Ouvre VlogMe et démarre l'enregistrement immédiatement.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchRouter.shared.setPendingRecord()
        NotificationCenter.default.post(name: .vlogmeStartRecording, object: nil)
        return .result()
    }
}

/// Enregistre automatiquement le raccourci auprès du système (Siri / bouton Action / Raccourcis).
struct VlogMeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Filme un vlog avec \(.applicationName)",
                "Démarre un enregistrement \(.applicationName)",
                "\(.applicationName) filme"
            ],
            shortTitle: "Filmer",
            systemImageName: "record.circle.fill"
        )
    }
}
