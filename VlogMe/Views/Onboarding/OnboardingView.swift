import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject private var permissions: PermissionsManager
    var onFinish: () -> Void

    @State private var page = 0
    @State private var permissionsRequested = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    permissionsPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: page)

                pageIndicator
                    .padding(.top, 16)

                actionButton
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Page 1 · Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            MascotSpeech(message: "Salut, moi c'est Vlogo !\nJe vais t'aider à faire\nton premier vlog 🎬", size: 150, accessory: .wave)
                .padding(.bottom, 32)

            Text("Vlogge.")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("En quelques secondes.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentOrange)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2 · Features

    private var featuresPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Ce que tu vas\npouvoir faire")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 48)

            VStack(spacing: 32) {
                featureRow(
                    icon: "hand.tap.fill",
                    color: Color.accentOrange,
                    title: "Enregistre tes moments",
                    description: "Tape pour filmer, relâche pour couper. Aussi simple que ça."
                )
                featureRow(
                    icon: "scissors",
                    color: .blue,
                    title: "Montage automatique",
                    description: "Tes clips assemblés en un seul vlog prêt à partager."
                )
                featureRow(
                    icon: "arrow.up.forward.app.fill",
                    color: .green,
                    title: "Partage partout",
                    description: "Instagram, TikTok, Photos — en un seul tap."
                )
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(2)
            }
            Spacer()
        }
    }

    // MARK: - Page 3 · Permissions

    private var permissionsPage: some View {
        VStack(spacing: 0) {
            Spacer()

            MascotSpeech(message: "Dernière étape !\nAutorise ma caméra et\nmon micro pour qu'on filme 📸", size: 140, accessory: .camera)
                .padding(.bottom, 32)

            Text("Accès à ta caméra")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text("VlogMe a besoin d'accéder à ta caméra\net à ton micro pour filmer tes vlogs.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if permissions.anyDenied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Accès refusé — ouvre les Réglages pour l'activer.")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                }
                .padding(.top, 20)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == page ? Color.accentOrange : Color.white.opacity(0.25))
                    .frame(width: i == page ? 24 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
    }

    // MARK: - Action button

    private var actionButton: some View {
        Button {
            Task { await handleNext() }
        } label: {
            Text(buttonLabel)
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.accentOrange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var buttonLabel: String {
        switch page {
        case 0: return "Commencer →"
        case 1: return "Continuer →"
        case 2: return permissions.anyDenied ? "Ouvrir les Réglages" : "Autoriser l'accès"
        default: return "Continuer →"
        }
    }

    private func handleNext() async {
        if page < 2 {
            withAnimation { page += 1 }
        } else {
            if permissions.anyDenied {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
            } else if !permissionsRequested {
                permissionsRequested = true
                await permissions.request()
                permissions.refresh()
                if permissions.allGranted {
                    onFinish()
                }
            } else {
                onFinish()
            }
        }
    }
}
