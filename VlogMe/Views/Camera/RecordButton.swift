import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)

                RoundedRectangle(cornerRadius: isRecording ? 8 : 32)
                    .fill(Color.accentOrange)
                    .frame(
                        width: isRecording ? 34 : 64,
                        height: isRecording ? 34 : 64
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Couper le segment" : "Démarrer un segment")
    }
}
