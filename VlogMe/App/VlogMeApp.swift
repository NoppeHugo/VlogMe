import SwiftUI

@main
struct VlogMeApp: App {

    @StateObject private var store = VlogStore()
    @StateObject private var camera = CameraService()
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var entitlements = Entitlements()

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
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "vlogme", url.host == "record" else { return }
                    LaunchRouter.shared.setPendingRecord()
                    NotificationCenter.default.post(name: .vlogmeStartRecording, object: nil)
                }
        }
    }
}
