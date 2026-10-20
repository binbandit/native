import SwiftUI

/// One thing that takes up context, with its cost on the right (or nothing there, when the caller
/// puts an action beside it).
struct ContributorRow<Leading: View>: View {
    let title: String
    var detail: String?
    var tokens: String?
    var isMono = false
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: DS.Space.md) {
            leading
                .frame(width: UsageMetrics.swatchSize)
            Text(title)
                .font(isMono ? .dsMonoCaption : .dsBody)
                .foregroundStyle(isMono ? .dsTextSecondary : .dsTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if let detail {
                Text(detail)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.md)
            if let tokens {
                Text(tokens)
                    .font(isMono ? .dsCaption : .dsBody)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextSecondary)
            }
        }
        .frame(minHeight: DS.Size.controlXS - DS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

extension ContributorRow where Leading == Color {
    /// A row with an empty leading slot, so its title lines up with those that have one.
    init(title: String, detail: String? = nil, tokens: String?, isMono: Bool = false) {
        self.init(title: title, detail: detail, tokens: tokens, isMono: isMono) { Color.clear }
    }
}

/// A group of contributors' title and total, flush with the table above it.
struct ContributorSectionHeader: View {
    let title: String
    let tokens: String?

    var body: some View {
        HStack {
            Text(title)
                .monospacedDigit()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.md)
            if let tokens {
                Text(tokens)
                    .monospacedDigit()
            }
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextTertiary)
        .frame(minHeight: DS.Size.controlXS)
    }
}

/// "Show all 170 tools": reveals the rest of a long list in place.
struct ShowAllButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dsCaption)
                .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
                .padding(.leading, UsageMetrics.swatchSize + DS.Space.md)
                .frame(minHeight: DS.Size.controlXS - DS.Space.xs)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Contributor rows") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: 0) {
            ContributorSectionHeader(title: "Memory files", tokens: "2k")
            ContributorRow(title: "AGENTS.md", detail: "Project", tokens: "2k")
            ContributorRow(
                title: "/Users/preview/Developer/native/native/Views/Composer/AGENTS.md", detail: "Project",
                tokens: "640", isMono: true)
            ContributorRow(title: "review", detail: "User", tokens: nil)
            ShowAllButton(title: "Show all 14 skills") {}
        }
        .frame(width: 360)
    }
}
#endif
