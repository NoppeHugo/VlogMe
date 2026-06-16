import SwiftUI

struct RootView: View {

    @EnvironmentObject private var store: VlogStore
    @EnvironmentObject private var camera: CameraService
    @EnvironmentObject private var permissions: PermissionsManager

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showPreview = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
                .environmentObject(permissions)
            } else {
                NavigationStack {
                    Group {
                        if permissions.allGranted {
                            CameraScreen(camera: camera, store: store, showPreview: $showPreview)
                        } else {
                            PermissionGateView()
                        }
                    }
                    .navigationDestination(isPresented: $showPreview) {
                        PreviewScreen(store: store)
                    }
                }
            }
        }
        .task { permissions.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissions.refresh() }
        }
    }
}
