import SwiftUI
import UIKit

struct PermissionGateView: View {

    @EnvironmentObject private var permissions: PermissionsManager

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "camera.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentOrange)

                VStack(spacing: 12) {
                    Text("Caméra et micro")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("VlogMe a besoin d'accéder à la caméra et au micro pour enregistrer tes vlogs.\nTout reste en local sur ton iPhone.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineSpacing(3)
                }
                .padding(.horizontal, 32)

                Spacer()

                if permissions.anyDenied {
                    Button("Ouvrir les Réglages") { openSettings() }
                        .buttonStyle(OrangeButton())
                } else {
                    Button("Autoriser l'accès") {
                        Task { await permissions.request() }
                    }
                    .buttonStyle(OrangeButton())
                }

                Spacer().frame(height: 8)
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Styles partagés

struct OrangeButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.accentOrange.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
