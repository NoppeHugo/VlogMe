import WidgetKit
import SwiftUI

// MARK: - Timeline

struct RecordEntry: TimelineEntry {
    let date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry { RecordEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        completion(Timeline(entries: [RecordEntry(date: Date())], policy: .never))
    }
}

// MARK: - View

struct VlogMeWidgetView: View {
    let entry: RecordEntry

    // accentOrange (#FF6B00)
    private let orange = Color(red: 1.0, green: 0.42, blue: 0.0)
    private let bg     = Color(red: 0.05, green: 0.05, blue: 0.05)

    var body: some View {
        Link(destination: URL(string: "vlogme://record")!) {
            ZStack {
                bg
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 3)
                            .frame(width: 54, height: 54)
                        Circle()
                            .fill(orange)
                            .frame(width: 42, height: 42)
                    }
                    Text("Filmer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .containerBackground(bg, for: .widget)
    }
}

// MARK: - Widget

@main
struct VlogMeWidget: Widget {
    let kind = "VlogMeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            VlogMeWidgetView(entry: entry)
        }
        .configurationDisplayName("VlogMe")
        .description("Lance un enregistrement en un tap.")
        .supportedFamilies([.systemSmall])
    }
}
