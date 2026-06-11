import SwiftUI

struct SegmentStackView: View {

    let segments: [VideoSegment]
    let urlFor: (VideoSegment) -> URL
    let onRedoLast: () -> Void
    let onDeleteLast: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        let isLast = index == segments.count - 1
                        SegmentThumbnailView(
                            url: urlFor(segment),
                            index: index + 1,
                            duration: segment.durationSeconds,
                            isLast: isLast
                        )
                        .id(segment.id)
                        .contextMenu {
                            if isLast {
                                Button { onRedoLast() } label: {
                                    Label("Refaire", systemImage: "arrow.counterclockwise")
                                }
                                Button(role: .destructive) { onDeleteLast() } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: segments.count) { _, _ in
                if let last = segments.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .trailing) }
                }
            }
        }
        .frame(height: 88)
    }
}

private struct SegmentThumbnailView: View {
    let url: URL
    let index: Int
    let duration: Double
    let isLast: Bool

    @State private var image: UIImage?

    private var durationText: String {
        let s = Int(duration)
        return s >= 60 ? String(format: "%d:%02d", s / 60, s % 60) : "\(s)s"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.12))
                ProgressView().tint(.white)
            }

            // Duration bar at bottom
            Text(durationText)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.6))
        }
        .frame(width: 54, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topLeading) {
            Text("\(index)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isLast ? Color.accentOrange : Color.white.opacity(0.25), lineWidth: isLast ? 2 : 1)
        )
        .task(id: url) {
            image = await ThumbnailGenerator.thumbnail(for: url)
        }
    }
}
