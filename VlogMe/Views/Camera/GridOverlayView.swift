import SwiftUI

struct GridOverlayView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Canvas { ctx, _ in
                var path = Path()
                // Lignes verticales (1/3 et 2/3)
                for x in [w / 3, w * 2 / 3] {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                }
                // Lignes horizontales (1/3 et 2/3)
                for y in [h / 3, h * 2 / 3] {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
                ctx.stroke(path, with: .color(.white.opacity(0.32)), lineWidth: 0.6)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
