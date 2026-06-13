import SwiftUI

struct CountdownOverlayView: View {
    let value: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            Text("\(value)")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color.accentOrange.opacity(0.6), radius: 20)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: value)
        }
        .allowsHitTesting(false)
    }
}
