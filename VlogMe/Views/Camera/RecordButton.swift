import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Anneau pulse orange — actif uniquement pendant l'enregistrement
                if isRecording {
                    Circle()
                        .stroke(Color.accentOrange.opacity(0.5), lineWidth: 3)
                        .frame(width: 78, height: 78)
                        .scaleEffect(pulsing ? 1.24 : 1.0)
                        .opacity(pulsing ? 0.0 : 0.8)
                        .task {
                            while !Task.isCancelled {
                                withAnimation(.easeOut(duration: 0.9)) { pulsing = true }
                                try? await Task.sleep(nanoseconds: 900_000_000)
                                withAnimation(.linear(duration: 0.0)) { pulsing = false }
                                try? await Task.sleep(nanoseconds: 80_000_000)
                            }
                        }
                }

                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)

                RoundedRectangle(cornerRadius: isRecording ? 8 : 34)
                    .fill(Color.accentOrange)
                    .frame(
                        width: isRecording ? 34 : 64,
                        height: isRecording ? 34 : 64
                    )
                    .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isRecording)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Couper le segment" : "Démarrer un segment")
        .onChange(of: isRecording) { _, _ in pulsing = false }
    }
}
