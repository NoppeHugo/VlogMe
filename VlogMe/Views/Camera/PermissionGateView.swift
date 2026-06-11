import SwiftUI
import UIKit

/// Écran d'explication / autorisation des permissions (cf. §4 — états caméra/micro).
struct PermissionGateView: View {

    @EnvironmentObject private var permissions: PermissionsManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)

                Text("VlogMe a besoin de la caméra et du micro")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text("Pour filmer tes vlogs et enregistrer le son. Tout reste en local sur ton iPhone.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))

                if permissions.anyDenied {
                    Button("Ouvrir les Réglages") { openSettings() }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                } else {
                    Button("Autoriser") {
                        Task { await permissions.request() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
            }
            .padding(40)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
