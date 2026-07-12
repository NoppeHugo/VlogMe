import SwiftUI

/// Filigrane « VlogMe » affiché en surimpression sur la prévisualisation pour les
/// utilisateurs gratuits (l'incrustation Core Animation de l'export n'apparaît pas
/// pendant la lecture `AVPlayer`, on la simule donc ici). Passer à Pro le retire.
struct WatermarkOverlayView: View {
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.accentOrange)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
                Text("VlogMe")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .opacity(0.9)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
            .padding(.bottom, 60)
        }
        .allowsHitTesting(false)
    }
}
