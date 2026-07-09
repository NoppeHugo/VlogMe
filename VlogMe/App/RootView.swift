import SwiftUI

struct RootView: View {

    @EnvironmentObject private var store: VlogStore
    @EnvironmentObject private var camera: CameraService
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var collab: CollabSyncService

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showPreview = false

    var body: some View {
        content
    }

    private var content: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                    Analytics.track(.onboardingCompleted)
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
        .task {
            permissions.refresh()
            collab.configure(store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refresh()
                // Récupère les clips ajoutés par les autres participants pendant l'absence.
                Task { await collab.syncAll() }
            }
        }
        .alert(
            "Vlog rejoint 🎉",
            isPresented: Binding(
                get: { collab.justJoinedVlogName != nil },
                set: { if !$0 { collab.justJoinedVlogName = nil } }
            ),
            presenting: collab.justJoinedVlogName
        ) { _ in
            Button("C'est parti", role: .cancel) { collab.justJoinedVlogName = nil }
        } message: { name in
            Text("Tu participes maintenant à « \(name) ». Filme tes clips — ils se synchroniseront avec ceux des autres.")
        }
    }
}
