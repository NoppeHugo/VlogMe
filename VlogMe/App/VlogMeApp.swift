import SwiftUI

@main
struct VlogMeApp: App {

    @StateObject private var store = VlogStore()
    @StateObject private var camera = CameraService()
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var entitlements = Entitlements()

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
                    NotificationCenter.default.post(name: .vlogmeStartRecording, object: nil)
                }
        }
    }
}
