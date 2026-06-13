import SwiftUI

struct SegmentReorderSheet: View {

    @EnvironmentObject private var store: VlogStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.segments) { seg in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.white.opacity(0.4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clip \((store.segments.firstIndex(where: { $0.id == seg.id }) ?? 0) + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(formatDuration(seg.effectiveDuration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.white.opacity(0.06))
                    .listRowSeparatorTint(.white.opacity(0.1))
                }
                .onMove { store.moveSegment(from: $0, to: $1) }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Réorganiser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .foregroundStyle(Color.accentOrange)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t < 60 ? "\(t) s" : String(format: "%d:%02d", t / 60, t % 60)
    }
}
