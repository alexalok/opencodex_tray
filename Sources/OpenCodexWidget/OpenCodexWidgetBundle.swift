import SwiftUI
import WidgetKit

private struct OpenCodexQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenCodexQuota", provider: QuotaWidgetTimelineProvider()) { entry in
            Group {
                switch entry.content {
                case .snapshot:
                    Text("OpenCodex Quota")
                case .unavailable:
                    Text("Unable to load")
                }
            }
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
