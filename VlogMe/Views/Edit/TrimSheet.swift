import SwiftUI
import AVKit

struct TrimSheet: View {

    let segment: VideoSegment
    let url: URL
    let onApply: (Double, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startValue: Double
    @State private var endValue: Double

    init(segment: VideoSegment, url: URL, onApply: @escaping (Double, Double?) -> Void) {
        self.segment = segment
        self.url = url
        self.onApply = onApply
        _startValue = State(initialValue: segment.trimStart ?? 0)
        _endValue   = State(initialValue: segment.trimEnd ?? segment.durationSeconds)
    }

    private var trimmedDuration: Double { max(0, endValue - startValue) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 28) {
                    // Aperçu vidéo
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)

                    VStack(spacing: 20) {
                        // Slider début
                        sliderRow(
                            label: "Début",
                            value: $startValue,
                            range: 0...(endValue - 0.5),
                            color: Color.accentOrange
                        )
                        // Slider fin
                        sliderRow(
                            label: "Fin",
                            value: $endValue,
                            range: (startValue + 0.5)...segment.durationSeconds,
                            color: .white
                        )
                    }
                    .padding(.horizontal, 24)

                    // Durée résultante
                    Text("Durée : \(formatDuration(trimmedDuration))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button {
                        let end = abs(endValue - segment.durationSeconds) < 0.1 ? nil : endValue
                        onApply(startValue, end)
                        dismiss()
                    } label: {
                        Text("Appliquer")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentOrange, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Rogner le clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Réinitialiser") {
                        startValue = 0
                        endValue   = segment.durationSeconds
                    }
                    .foregroundStyle(Color.accentOrange)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(formatDuration(value.wrappedValue))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }
            Slider(value: value, in: range)
                .tint(color)
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t < 60 ? "\(t) s" : String(format: "%d:%02d", t / 60, t % 60)
    }
}
