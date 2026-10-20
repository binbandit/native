import SwiftUI

/// The `IconThemePicker` popover: one row per option, the current one checked. It works like a
/// menu: the pointer or the arrow keys highlight a row, a click or Return chooses it and closes.
struct IconThemeList<ID: Hashable>: View {
    let title: String
    @Binding var selection: ID
    let options: [IconThemeOption<ID>]
    let isDark: Bool
    let onClose: () -> Void

    @State private var highlighted: ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options) { option in
                        row(option)
                            .id(option.id)
                    }
                }
                .padding(DS.Space.xs)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: DS.IconPicker.listWidth)
            .frame(maxHeight: DS.IconPicker.listMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(by: -1, scroller) }
            .onKeyPress(.downArrow) { move(by: 1, scroller) }
            .onKeyPress(.return) { choose(highlighted) }
            .onKeyPress(.space) { choose(highlighted) }
            .onAppear {
                highlighted = selection
                scroller.scrollTo(selection, anchor: .center)
                isFocused = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func row(_ option: IconThemeOption<ID>) -> some View {
        let isSelected = option.id == selection
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        return Button {
            select(option.id)
        } label: {
            HStack(spacing: DS.Space.md) {
                IconThemeThumbnail(image: option.image(isDark: isDark), size: DS.IconPicker.rowThumbnail)
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.title)
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextPrimary)
                    if let detail = option.detail {
                        Text(detail)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.dsAccentText)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(height: DS.IconPicker.rowHeight)
            .background(highlighted == option.id ? Color.dsHover : .clear, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { highlighted = option.id }
        }
        .accessibilityLabel(option.title)
        .accessibilityValue(option.detail ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func move(by step: Int, _ scroller: ScrollViewProxy) -> KeyPress.Result {
        let ids = options.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let index = highlighted.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : ids.count)
        let next = ids[min(max(index + step, 0), ids.count - 1)]
        highlighted = next
        scroller.scrollTo(next)
        return .handled
    }

    private func choose(_ id: ID?) -> KeyPress.Result {
        guard let id else { return .ignored }
        select(id)
        return .handled
    }

    private func select(_ id: ID) {
        selection = id
        onClose()
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Icon theme list") {
    DSPreviewPair {
        IconThemeList(
            title: "App icon", selection: .constant("cobalt"), options: GalleryIconThemePicker.options, isDark: false,
            onClose: {}
        )
        .frame(width: 320)
    }
}
#endif
