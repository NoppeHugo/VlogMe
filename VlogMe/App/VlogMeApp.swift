import SwiftUI
import CloudKit
import UIKit

@main
struct VlogMeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var store = VlogStore()
    @StateObject private var camera = CameraService()
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var entitlements = Entitlements()
    @StateObject private var collab = CollabSyncService.shared

    init() {
        Analytics.configure()
        Analytics.track(.appOpened)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(camera)
                .environmentObject(permissions)
                .environmentObject(entitlements)
                .environmentObject(collab)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "vlogme", url.host == "record" else { return }
                    LaunchRouter.shared.setPendingRecord()
                    NotificationCenter.default.post(name: .vlogmeStartRecording, object: nil)
                }
        }
    }
}

// MARK: - App & Scene delegates (invitations iCloud + push silencieux CloudKit)

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// Push silencieux CloudKit : un participant a ajouté un clip → on synchronise.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if CKNotification(fromRemoteNotificationDictionary: userInfo) != nil {
            Task { @MainActor in CollabSyncService.shared.handleRemoteNotification() }
        }
        completionHandler(.newData)
    }

    /// Lien d'invitation ouvert alors que l'app n'était pas lancée.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await CollabSyncService.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    /// Lien d'invitation ouvert pendant que l'app tourne.
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await CollabSyncService.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}
