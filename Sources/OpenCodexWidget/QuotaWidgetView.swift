import AppKit
import PauseWorkerCore
import SwiftUI
import WidgetKit

// MARK: - Style system

private enum WidgetPalette {
    static let claude = Color(red: 0.83, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.10, green: 0.62, blue: 0.55)
}

/// Visible quota period qualifier. Spoken semantics come from the
/// view model's accessibility labels, so this text stays decorative.
private enum PeriodQualifier: String {
    case claude = "5h / 1w"
}

/// Non-quantitative provider accent: a slim tinted rail on the leading edge.
private struct AccentRail: ViewModifier {
    let tint: Color
    let dimmed: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: 3)
                    .opacity(dimmed ? 0.45 : 1)
                    .accessibilityHidden(true)
            }
    }
}

// MARK: - Root view

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
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker()
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("Unable to load")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker()

            Spacer(minLength: 6)

            ProviderBlock(
                name: "Claude",
                iconName: "ProviderIcon-claude",
                fallback: "C",
                qualifier: .claude,
                provider: model.claude,
                tint: WidgetPalette.claude,
                dimmed: model.isStale
            )

            Spacer(minLength: 8)

            ProviderBlock(
                name: "Codex",
                iconName: "ProviderIcon-codex",
                fallback: "O",
                qualifier: nil,
                provider: model.codex,
                tint: WidgetPalette.codex,
                dimmed: model.isStale
            )

            Spacer(minLength: 8)

            UpdatedAgeView(
                updatedAt: model.updatedAt,
                referenceDate: entry.date,
                isStale: model.isStale
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                WidgetKicker()
                Spacer(minLength: 8)
                UpdatedAgeView(
                    updatedAt: model.updatedAt,
                    referenceDate: entry.date,
                    isStale: model.isStale
                )
            }

            HStack(alignment: .top, spacing: 12) {
                ProviderColumn(
                    name: "Claude",
                    iconName: "ProviderIcon-claude",
                    fallback: "C",
                    qualifier: .claude,
                    provider: model.claude,
                    tint: WidgetPalette.claude,
                    dimmed: model.isStale
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)

                ProviderColumn(
                    name: "Codex",
                    iconName: "ProviderIcon-codex",
                    fallback: "O",
                    qualifier: nil,
                    provider: model.codex,
                    tint: WidgetPalette.codex,
                    dimmed: model.isStale
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Building blocks

private struct WidgetKicker: View {
    var body: some View {
        Text("OpenCodex Quota")
            .textCase(.uppercase)
            .font(.caption2.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("OpenCodex Quota")
    }
}

private struct ProviderHeaderRow: View {
    let name: String
    let iconName: String
    let fallback: String
    let qualifier: PeriodQualifier?
    let provider: QuotaWidgetProviderModel
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(name: iconName, fallback: fallback, size: 14)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                if provider.isUnavailable {
                    Text(provider.total)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(provider.total)
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                }
                if let qualifier {
                    Text(qualifier.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.accessibilityLabel)
    }
}

private struct ProviderBlock: View {
    let name: String
    let iconName: String
    let fallback: String
    let qualifier: PeriodQualifier?
    let provider: QuotaWidgetProviderModel
    let tint: Color
    let dimmed: Bool

    var body: some View {
        ProviderHeaderRow(
            name: name,
            iconName: iconName,
            fallback: fallback,
            qualifier: qualifier,
            provider: provider,
            dimmed: dimmed
        )
        .modifier(AccentRail(tint: tint, dimmed: dimmed))
    }
}

private struct ProviderColumn: View {
    let name: String
    let iconName: String
    let fallback: String
    let qualifier: PeriodQualifier?
    let provider: QuotaWidgetProviderModel
    let tint: Color
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProviderHeaderRow(
                name: name,
                iconName: iconName,
                fallback: fallback,
                qualifier: qualifier,
                provider: provider,
                dimmed: dimmed
            )

            if !provider.isUnavailable {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(provider.rows) { row in
                        HStack(spacing: 6) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(row.value)
                                .font(.caption)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.accessibilityLabel)
                    }

                    if provider.overflowCount > 0 {
                        Text("+\(provider.overflowCount) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .modifier(AccentRail(tint: tint, dimmed: dimmed))
    }
}

private struct UpdatedAgeView: View {
    let updatedAt: Date?
    let referenceDate: Date
    let isStale: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(prefix: true, staleText: true)
            content(prefix: false, staleText: true)
            content(prefix: false, staleText: false)
        }
        .font(.caption2)
        .lineLimit(1)
    }

    @ViewBuilder
    private func content(prefix: Bool, staleText: Bool) -> some View {
        HStack(spacing: 6) {
            if let age = QuotaWidgetAgeText.make(
                updatedAt: updatedAt,
                relativeTo: referenceDate
            ) {
                HStack(spacing: 4) {
                    if prefix {
                        Text("Updated")
                    }
                    Text(age.display)
                }
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(age.accessibilityLabel)
            }
            if isStale {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8, weight: .semibold))
                        .accessibilityHidden(true)
                    if staleText {
                        Text("Stale")
                    }
                }
                .foregroundStyle(.orange)
                .accessibilityLabel("Stale")
            }
        }
    }
}

private struct ProviderIcon: View {
    let name: String
    let fallback: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.templateImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
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

    /// Loads the provider artwork as a template image so it adapts to
    /// light and dark appearances via the foreground style.
    private static func templateImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url),
              let template = image.copy() as? NSImage
        else { return nil }
        template.isTemplate = true
        return template
    }
}
