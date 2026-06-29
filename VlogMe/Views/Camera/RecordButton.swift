import SwiftUI

/// Bouton d'enregistrement façon caméra Apple :
/// - réaction au toucher (le bouton « s'enfonce » avec un ressort) ;
/// - morph disque plein → carré arrondi en spring ;
/// - halo orange qui respire pendant la capture ;
/// - haptique en deux temps : tick léger au toucher, impact franc à la bascule.
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RecordButtonFace(isRecording: isRecording)
        }
        .buttonStyle(RecordButtonStyle())
        .frame(width: 96, height: 96)
        .contentShape(Circle())
        .accessibilityLabel(isRecording ? "Couper le segment" : "Démarrer un segment")
        .accessibilityAddTraits(.startsMediaSession)
        // Confirmation tactile : impact ferme au démarrage, plus doux à l'arrêt.
        .sensoryFeedback(trigger: isRecording) { _, recording in
            recording ? .impact(weight: .heavy, intensity: 1.0)
                      : .impact(flexibility: .solid, intensity: 0.6)
        }
    }
}

// MARK: - Face du bouton (morph + halo)

private struct RecordButtonFace: View {
    let isRecording: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Halo qui respire — visible uniquement pendant l'enregistrement.
            Circle()
                .stroke(Color.accentOrange.opacity(0.5), lineWidth: 3)
                .frame(width: 78, height: 78)
                .scaleEffect(pulse ? 1.22 : 1.0)
                .opacity(isRecording ? (pulse ? 0.0 : 0.7) : 0.0)

            // Anneau blanc fixe.
            Circle()
                .stroke(.white, lineWidth: 4)
                .frame(width: 78, height: 78)

            // Cœur orange : disque plein (repos) → carré arrondi (capture).
            RoundedRectangle(cornerRadius: isRecording ? 9 : 32, style: .continuous)
                .fill(Color.accentOrange)
                .frame(
                    width: isRecording ? 30 : 64,
                    height: isRecording ? 30 : 64
                )
        }
        // Spring légèrement rebondi pour la « sensation » du morph.
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isRecording)
        // .task(id:) redémarre/annule proprement la boucle de pulse quand l'état change.
        .task(id: isRecording) {
            pulse = false
            guard isRecording else { return }
            try? await Task.sleep(nanoseconds: 120_000_000) // laisse le morph se poser
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 1.0)) { pulse = true }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                pulse = false
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }
}

// MARK: - Style : enfoncement au toucher

private struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
            // Tick discret dès le contact — la sensation de « give ».
            .sensoryFeedback(.impact(weight: .light, intensity: 0.45),
                             trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
