import SwiftUI

/// Splash de branding affiché par-dessus l'UILaunchScreen (fond blanc),
/// puis fondu vers le contenu. Reprend la mascotte + le wordmark "vlogme".
struct SplashView: View {

    var onFinish: () -> Void

    @State private var appeared = false
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 20) {
                MascotView(size: 130, accessory: .camera)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)

                wordmark
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }
        }
        .opacity(fadeOut ? 0 : 1)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.4)) { fadeOut = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: onFinish)
            }
        }
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("vlog")
                .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.10))
            Text("me")
                .foregroundStyle(Color.accentOrange)
        }
        .font(.system(size: 40, weight: .black, design: .rounded))
    }
}
