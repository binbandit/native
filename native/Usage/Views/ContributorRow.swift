import SwiftUI

/// One thing that takes up context, with its cost on the right.
struct ContributorRow<Leading: View>: View {
    let title: String
    var detail: String?
    let tokens: String
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
            Text(tokens)
                .font(isMono ? .dsCaption : .dsBody)
                .monospacedDigit()
                .foregroundStyle(.dsTextSecondary)
        }
        .frame(minHeight: DS.Size.controlXS - DS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

extension ContributorRow where Leading == Color {
    /// A row with an empty leading slot, so its title lines up with those that have one.
    init(title: String, detail: String? = nil, tokens: String, isMono: Bool = false) {
        self.init(title: title, detail: detail, tokens: tokens, isMono: isMono) { Color.clear }
    }
}

/// A group of contributors' title and total, flush with the table above it.
struct ContributorSectionHeader: View {
    let title: String
    let tokens: String

    var body: some View {
        HStack {
            Text(title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.md)
            Text(tokens)
                .monospacedDigit()
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
