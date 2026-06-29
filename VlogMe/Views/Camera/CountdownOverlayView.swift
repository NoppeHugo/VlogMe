import SwiftUI

/// Compte à rebours façon caméra Apple : chaque seconde, le chiffre « pope »
/// en ressort, un anneau orange s'étend derrière lui, et un tick haptique
/// rythme la descente.
struct CountdownOverlayView: View {
    let value: Int

    @State private var ringPulse = false
    @State private var pop: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            // Anneau qui s'étend et s'estompe à chaque seconde.
            Circle()
                .stroke(Color.accentOrange.opacity(0.55), lineWidth: 4)
                .frame(width: 170, height: 170)
                .scaleEffect(ringPulse ? 1.6 : 0.75)
                .opacity(ringPulse ? 0 : 0.85)

            Text("\(value)")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color.accentOrange.opacity(0.6), radius: 20)
                .contentTransition(.numericText(countsDown: true))
                .scaleEffect(pop)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
        }
        .allowsHitTesting(false)
        // Tick haptique à chaque seconde.
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: value)
        .task(id: value) {
            ringPulse = false
            pop = 1.25
            withAnimation(.easeOut(duration: 0.85)) { ringPulse = true }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { pop = 1.0 }
        }
    }
}
