import Foundation
import PostHog

/// Couche analytics (PostHog). Tous les events produit passent ici.
///
/// Configuration : renseigne `POSTHOG_API_KEY` (et éventuellement `POSTHOG_HOST`)
/// dans Info.plist. Si la clé est absente/vide, Analytics ne fait rien (no-op) —
/// l'app fonctionne normalement sans tracking.
enum Analytics {

    // MARK: - Events

    enum Event: String {
        case appOpened              = "app_opened"
        case onboardingCompleted    = "onboarding_completed"
        case recordingStarted       = "recording_started"
        case vlogExported           = "vlog_exported"
        case firstVlogExported      = "first_vlog_exported"
        case freeLimitReached       = "free_limit_reached"
        case paywallShown           = "paywall_shown"
        case purchaseCompleted      = "purchase_completed"
        case purchaseRestored       = "purchase_restored"
        case reviewPromptShown      = "review_prompt_shown"
        case reviewRated            = "review_rated"
        case sharedToInstagram      = "shared_to_instagram"
        case sharedToTikTok         = "shared_to_tiktok"
        case savedToPhotos          = "saved_to_photos"
        case introConfigured        = "intro_configured"
        case hookToggled            = "hook_toggled"
        case transitionSelected     = "transition_selected"
        case beatSyncToggled        = "beat_sync_toggled"
        case templateApplied        = "template_applied"
    }

    private static var isEnabled = false

    // MARK: - Lifecycle

    static func configure() {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
            !key.isEmpty,
            !key.hasPrefix("$(")
        else { return }

        let host = (Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "https://eu.i.posthog.com"

        let config = PostHogConfig(apiKey: key, host: host)
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
        isEnabled = true
    }

    // MARK: - Tracking

    static func track(_ event: Event, _ properties: [String: Any] = [:]) {
        guard isEnabled else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    static func setPro(_ isPro: Bool) {
        guard isEnabled else { return }
        PostHogSDK.shared.register(["is_pro": isPro])
    }
}
