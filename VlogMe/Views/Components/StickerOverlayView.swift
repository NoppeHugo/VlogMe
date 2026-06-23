import SwiftUI

/// Superposition SwiftUI du sticker pour la **prévisualisation** (l'incrustation
/// Core Animation de l'export n'étant pas rendue par `AVPlayer`). Reproduit au
/// mieux l'apparence finale.
struct StickerOverlayView: View {
    let text: String
    let position: StickerPosition
    let style: StickerStyle

    var body: some View {
        if !text.isEmpty {
            VStack {
                if !position.isTop { Spacer() }
                HStack {
                    if !position.isLeading { Spacer() }
                    chip
                    if position.isLeading { Spacer() }
                }
                if position.isTop { Spacer() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var chip: some View {
        switch style {
        case .pill:
            label(textColor: Color(white: 0.1))
                .background(.white.opacity(0.85), in: Capsule())
        case .outline:
            label(textColor: .white)
                .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.5))
        case .accent:
            label(textColor: .black)
                .background(Color.accentOrange.opacity(0.95), in: Capsule())
        }
    }

    private func label(textColor: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
    }
}
