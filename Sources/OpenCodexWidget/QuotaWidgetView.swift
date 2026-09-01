import AppKit
import PauseWorkerCore
import SwiftUI
import WidgetKit

struct QuotaWidgetView: View {
    let entry: QuotaWidgetEntry

    @Environment(\.widgetFamily) private var family

    private var model: QuotaWidgetViewModel {
        QuotaWidgetViewModel(content: entry.content)
    }

    var body: some View {
        Group {
            if model.isUnavailable {
                unavailableLayout
            } else {
                switch family {
                case .systemMedium:
                    mediumLayout
                default:
                    smallLayout
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private var unavailableLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenCodex Quota")
                .font(.headline)
            Spacer()
            Text("Unable to load")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenCodex Quota")
                .font(.headline)
                .lineLimit(1)

            SmallProviderRow(
                name: "Claude",
                iconName: "ProviderIcon-claude",
                fallback: "C",
                qualifier: "5h / 1w",
                provider: model.claude
            )

            SmallProviderRow(
                name: "Codex",
                iconName: "ProviderIcon-codex",
                fallback: "O",
                qualifier: nil,
                provider: model.codex
            )

            Spacer(minLength: 0)
            UpdatedAgeView(updatedAt: model.updatedAt, isStale: model.isStale)
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("OpenCodex Quota")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                UpdatedAgeView(updatedAt: model.updatedAt, isStale: model.isStale)
            }

            HStack(alignment: .top, spacing: 16) {
                ProviderColumn(
                    name: "Claude",
                    iconName: "ProviderIcon-claude",
                    fallback: "C",
                    provider: model.claude
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ProviderColumn(
                    name: "Codex",
                    iconName: "ProviderIcon-codex",
                    fallback: "O",
                    provider: model.codex
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SmallProviderRow: View {
    let name: String
    let iconName: String
    let fallback: String
    let qualifier: String?
    let provider: QuotaWidgetProviderModel

    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(name: iconName, fallback: fallback, size: 16)
            Text(name)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                if let qualifier {
                    Text(qualifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(provider.total)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel("\(name) \(provider.total)")
            }
        }
    }
}

private struct ProviderColumn: View {
    let name: String
    let iconName: String
    let fallback: String
    let provider: QuotaWidgetProviderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ProviderIcon(name: iconName, fallback: fallback, size: 15)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(provider.total)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("\(name) \(provider.total)")
            }

            if !provider.isUnavailable {
                ForEach(provider.rows) { row in
                    HStack(spacing: 5) {
                        Text(row.label)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(row.value)
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityLabel("\(name) \(row.label) \(row.value)")
                    }
                }

                if provider.overflowCount > 0 {
                    Text("+\(provider.overflowCount) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct UpdatedAgeView: View {
    let updatedAt: Date?
    let isStale: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let updatedAt {
                Text("Updated")
                Text(updatedAt, style: .relative)
            }
            if isStale {
                Text("Stale")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct ProviderIcon: View {
    let name: String
    let fallback: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(fallback)
                    .font(.caption2.bold())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static func image(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
