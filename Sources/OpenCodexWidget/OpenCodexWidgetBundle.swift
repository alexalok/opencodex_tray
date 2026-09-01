import SwiftUI
import WidgetKit

private struct WiringEntry: TimelineEntry {
    let date: Date
}

private struct WiringProvider: TimelineProvider {
    func placeholder(in context: Context) -> WiringEntry {
        WiringEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WiringEntry) -> Void
    ) {
        completion(WiringEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WiringEntry>) -> Void
    ) {
        completion(Timeline(entries: [WiringEntry(date: .now)], policy: .never))
    }
}

private struct OpenCodexQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenCodexQuota", provider: WiringProvider()) { _ in
            Text("OpenCodex Quota")
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("OpenCodex Quota")
        .description("Codex and Claude quota remaining.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OpenCodexWidgetBundle: WidgetBundle {
    var body: some Widget {
        OpenCodexQuotaWidget()
    }
}
