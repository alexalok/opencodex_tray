import SwiftUI
import WidgetKit

private struct OpenCodexQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenCodexQuota", provider: QuotaWidgetTimelineProvider()) { entry in
            QuotaWidgetView(entry: entry)
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
