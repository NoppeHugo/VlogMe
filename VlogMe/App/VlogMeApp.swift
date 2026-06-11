import SwiftUI

@main
struct VlogMeApp: App {

    // Racine de composition : les trois services partagés vivent ici.
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
        }
    }
}
