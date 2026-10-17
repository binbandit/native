import SwiftUI

/// One thing that takes up context, with its cost on the right.
struct ContributorRow<Leading: View>: View {
    let title: String
    var detail: String?
    let tokens: String
    var isMono = false
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            leading
                .frame(width: DS.Space.md)
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

extension ContributorRow where Leading == EmptyView {
    init(title: String, detail: String? = nil, tokens: String, isMono: Bool = false) {
        self.init(title: title, detail: detail, tokens: tokens, isMono: isMono) { EmptyView() }
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
                .padding(.leading, DS.Space.md + DS.Space.sm)
                .frame(minHeight: DS.Size.controlXS - DS.Space.xs)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
    }
}
