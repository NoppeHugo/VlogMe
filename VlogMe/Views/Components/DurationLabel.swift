import SwiftUI

/// Affiche une durée en mm:ss (compteur de durée totale cumulée, §4).
struct DurationLabel: View {
    let seconds: Double
    var isRecording: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
            }
            Text(formatted)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private var formatted: String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
