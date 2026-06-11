import SwiftUI

/// Navigation de la coque : Caméra → Prévisualisation (cf. §1 — trois écrans, pas un de plus).
struct RootView: View {

    @EnvironmentObject private var store: VlogStore
    @EnvironmentObject private var camera: CameraService
    @EnvironmentObject private var permissions: PermissionsManager

    @Environment(\.scenePhase) private var scenePhase
    @State private var showPreview = false

    var body: some View {
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
        .task { permissions.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissions.refresh() }
        }
    }
}
