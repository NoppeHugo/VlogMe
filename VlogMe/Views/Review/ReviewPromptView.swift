import SwiftUI
import StoreKit

/// Écran de review présenté après le 1er vlog exporté.
/// Pré-question douce : si l'user met 4–5★ → prompt App Store natif. Sinon → feedback interne.
struct ReviewPromptView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var rating = 0
    @State private var step: Step = .asking
    @State private var feedback = ""

    enum Step { case asking, happy, feedback }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                MascotSpeech(message: mascotMessage, size: 120, accessory: .star)

                if step == .asking {
                    stars
                        .padding(.top, 8)
                    Text("Touche les étoiles pour noter")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.4))
                }

                if step == .feedback {
                    feedbackField
                }

                Spacer()

                actionArea
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear { Analytics.track(.reviewPromptShown) }
    }

    // MARK: - Mascot message

    private var mascotMessage: String {
        switch step {
        case .asking:   return "Bravo pour ton premier vlog ! 🎉\nTu aimes VlogMe ?"
        case .happy:    return "Trop cool ! Tu peux nous\nmettre 5★ sur l'App Store ?"
        case .feedback: return "Oh non… dis-nous ce qui\nn'allait pas, on va l'améliorer !"
        }
    }

    // MARK: - Stars

    private var stars: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: 36))
                    .foregroundStyle(i <= rating ? Color.accentOrange : .white.opacity(0.3))
                    .scaleEffect(i <= rating ? 1.0 : 0.9)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            rating = i
                        }
                        handleRating(i)
                    }
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }

    private func handleRating(_ value: Int) {
        Analytics.track(.reviewRated, ["stars": value])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            step = value >= 4 ? .happy : .feedback
        }
    }

    // MARK: - Feedback field

    private var feedbackField: some View {
        TextField("Ton retour (optionnel)…", text: $feedback, axis: .vertical)
            .lineLimit(3...5)
            .padding(14)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
    }

    // MARK: - Action area

    @ViewBuilder
    private var actionArea: some View {
        switch step {
        case .asking:
            Button("Plus tard") { dismiss() }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))

        case .happy:
            VStack(spacing: 12) {
                Button {
                    requestReview()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
                } label: {
                    Text("Noter sur l'App Store ⭐️")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentOrange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button("Plus tard") { dismiss() }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
            }

        case .feedback:
            VStack(spacing: 12) {
                Button {
                    // TODO: envoyer le feedback (mail / backend) — pour l'instant on remercie
                    dismiss()
                } label: {
                    Text("Envoyer")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentOrange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button("Passer") { dismiss() }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
