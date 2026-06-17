import SwiftUI

/// Petit bonhomme orange — mascotte de VlogMe.
/// Dessiné vectoriellement (aucune image requise), avec animation idle (respiration + clignement).
struct MascotView: View {

    enum Accessory {
        case camera   // tient une petite caméra
        case star     // brandit une étoile (écran de review)
        case wave     // salue (un bras levé)
        case none
    }

    var size: CGFloat = 140
    var accessory: Accessory = .camera

    @State private var breathe = false
    @State private var blink = false
    @State private var wiggle = false

    var body: some View {
        ZStack {
            body(s: size)
        }
        .frame(width: size, height: size * 1.15)
        .scaleEffect(y: breathe ? 1.02 : 0.98, anchor: .bottom)
        .rotationEffect(.degrees(wiggle ? 2 : -2), anchor: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                wiggle = true
            }
            scheduleBlink()
        }
    }

    // MARK: - Composition

    private func body(s: CGFloat) -> some View {
        ZStack {
            // Ombre portée
            Ellipse()
                .fill(.black.opacity(0.25))
                .frame(width: s * 0.72, height: s * 0.12)
                .offset(y: s * 0.56)
                .blur(radius: 4)

            // Pieds
            Capsule().fill(footColor).frame(width: s * 0.16, height: s * 0.10)
                .offset(x: -s * 0.16, y: s * 0.49)
            Capsule().fill(footColor).frame(width: s * 0.16, height: s * 0.10)
                .offset(x:  s * 0.16, y: s * 0.49)

            // Bras qui salue (pose wave)
            if accessory == .wave {
                Capsule().fill(bodyColor)
                    .frame(width: s * 0.10, height: s * 0.30)
                    .rotationEffect(.degrees(wiggle ? 22 : 8), anchor: .bottom)
                    .offset(x: s * 0.34, y: -s * 0.14)
            }

            // Corps / tête (un seul blob arrondi)
            RoundedRectangle(cornerRadius: s * 0.38, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.52, blue: 0.34), bodyColor],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: s * 0.78, height: s * 0.86)
                .overlay(
                    RoundedRectangle(cornerRadius: s * 0.38, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: s * 0.012)
                )

            // Joues
            Circle().fill(Color(red: 1.0, green: 0.45, blue: 0.45).opacity(0.45))
                .frame(width: s * 0.12, height: s * 0.12)
                .offset(x: -s * 0.22, y: s * 0.02)
            Circle().fill(Color(red: 1.0, green: 0.45, blue: 0.45).opacity(0.45))
                .frame(width: s * 0.12, height: s * 0.12)
                .offset(x:  s * 0.22, y: s * 0.02)

            // Yeux
            eye(s: s, dx: -s * 0.15)
            eye(s: s, dx:  s * 0.15)

            // Sourire
            Smile()
                .stroke(Color(red: 0.25, green: 0.10, blue: 0.05), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
                .frame(width: s * 0.26, height: s * 0.14)
                .offset(y: s * 0.10)

            // Accessoires
            switch accessory {
            case .camera: cameraProp(s: s)
            case .star:   starProp(s: s)
            case .wave, .none: EmptyView()
            }
        }
    }

    private func eye(s: CGFloat, dx: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(.white)
                .frame(width: s * 0.14, height: blink ? s * 0.015 : s * 0.17)
            if !blink {
                Circle()
                    .fill(Color(red: 0.18, green: 0.08, blue: 0.04))
                    .frame(width: s * 0.075, height: s * 0.075)
                    .overlay(Circle().fill(.white).frame(width: s * 0.025, height: s * 0.025).offset(x: -s * 0.015, y: -s * 0.015))
            }
        }
        .offset(x: dx, y: -s * 0.12)
        .animation(.easeInOut(duration: 0.08), value: blink)
    }

    // MARK: - Caméra tenue

    private func cameraProp(s: CGFloat) -> some View {
        ZStack {
            // Mains
            Circle().fill(bodyColor).frame(width: s * 0.13, height: s * 0.13).offset(x: -s * 0.26, y: s * 0.28)
            Circle().fill(bodyColor).frame(width: s * 0.13, height: s * 0.13).offset(x:  s * 0.26, y: s * 0.28)

            // Corps caméra
            RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                .frame(width: s * 0.46, height: s * 0.27)
                .overlay(
                    // Viseur
                    RoundedRectangle(cornerRadius: s * 0.02)
                        .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                        .frame(width: s * 0.14, height: s * 0.06)
                        .offset(x: s * 0.05, y: -s * 0.15)
                )
                .overlay(
                    // Objectif
                    Circle()
                        .fill(RadialGradient(colors: [Color.accentOrange, .black], center: .center, startRadius: 0, endRadius: s * 0.09))
                        .frame(width: s * 0.16, height: s * 0.16)
                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: s * 0.01))
                        .offset(x: -s * 0.04)
                )
                .overlay(
                    // Témoin rec
                    Circle().fill(.red).frame(width: s * 0.03, height: s * 0.03)
                        .offset(x: s * 0.16, y: -s * 0.07)
                )
                .offset(y: s * 0.30)
        }
    }

    // MARK: - Étoile brandie

    private func starProp(s: CGFloat) -> some View {
        Image(systemName: "star.fill")
            .font(.system(size: s * 0.28, weight: .bold))
            .foregroundStyle(
                LinearGradient(colors: [.yellow, Color.accentOrange], startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .yellow.opacity(0.5), radius: s * 0.05)
            .rotationEffect(.degrees(wiggle ? 8 : -8))
            .offset(x: s * 0.28, y: -s * 0.32)
    }

    // MARK: - Helpers

    private var bodyColor: Color { Color.accentOrange }
    private var footColor: Color { Color(red: 0.85, green: 0.32, blue: 0.18) }

    private func scheduleBlink() {
        let delay = Double.random(in: 2.0...4.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                blink = false
                scheduleBlink()
            }
        }
    }
}

/// Tracé du sourire (arc vers le bas).
private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.6)
        )
        return p
    }
}

/// Mascotte + bulle de dialogue, pour l'onboarding.
struct MascotSpeech: View {
    let message: String
    var size: CGFloat = 130
    var accessory: MascotView.Accessory = .camera

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Bulle
            Text(message)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    SpeechBubble()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                )
                .padding(.horizontal, 24)
                .scaleEffect(appeared ? 1 : 0.8, anchor: .bottom)
                .opacity(appeared ? 1 : 0)

            MascotView(size: size, accessory: accessory)
                .offset(y: -4)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15)) {
                appeared = true
            }
        }
    }
}

/// Bulle de dialogue avec petite pointe en bas.
private struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = 12
        let bubble = rect.insetBy(dx: 0, dy: 0)
        let body = CGRect(x: bubble.minX, y: bubble.minY, width: bubble.width, height: bubble.height - tail)
        var p = Path(roundedRect: body, cornerRadius: r)
        // Pointe
        let cx = rect.midX
        var tailPath = Path()
        tailPath.move(to: CGPoint(x: cx - tail, y: body.maxY - 2))
        tailPath.addLine(to: CGPoint(x: cx, y: body.maxY + tail))
        tailPath.addLine(to: CGPoint(x: cx + tail, y: body.maxY - 2))
        tailPath.closeSubpath()
        p.addPath(tailPath)
        return p
    }
}
