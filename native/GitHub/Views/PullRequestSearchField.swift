import SwiftUI

/// Filters the list as you type: title, `owner/name#number`, branch, author or label.
struct PullRequestSearchField: View {
    @Binding var query: String

    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        TextField("Filter", text: $query, prompt: Text("Filter pull requests").foregroundStyle(.dsTextTertiary))
            .textFieldStyle(.plain)
            .font(.dsBody)
            .foregroundStyle(.dsTextPrimary)
            .focused($isFocused)
            .padding(.leading, DS.Space.xxl + DS.Space.xxs)
            .padding(.trailing, DS.Space.xxl)
            .frame(width: DS.Size.sidebarWidth - DS.Space.xxxl, height: DS.Size.controlSM)
            .overlay(alignment: .leading) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: DS.Size.navIcon - DS.Space.xxs))
                    .foregroundStyle(.dsTextTertiary)
                    .padding(.leading, DS.Space.md + DS.Space.xxs)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .trailing) {
                if !query.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .font(.system(size: DS.Size.navIcon))
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.trailing, DS.Space.md)
                }
            }
            .background(.dsSurface, in: shape)
            .overlay { shape.strokeBorder(isFocused ? Color.dsAccent : Color.dsBorder, lineWidth: 1) }
            .onKeyPress(.escape) {
                guard !query.isEmpty else { return .ignored }
                query = ""
                return .handled
            }
    }
}
