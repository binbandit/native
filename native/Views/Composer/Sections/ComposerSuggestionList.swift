import SwiftUI

/// A list floating above the composer, like the reference app's suggestion lists: slash commands, files to
/// mention. The editor keeps focus and drives the highlight with the arrow keys; Return or Tab
/// inserts the highlighted item, a click inserts any.
struct ComposerSuggestionList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @Binding var highlighted: Int
    let onChoose: (Item) -> Void
    @ViewBuilder let row: (Item, _ isHighlighted: Bool) -> Row

    var body: some View {
        ComposerSurface(isFloating: true) {
            ScrollViewReader { proxy in
                CappedHeightScrollView(maxHeight: ComposerMetrics.suggestionListMaxHeight) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            button(item, at: index)
                                .id(index)
                        }
                    }
                    .padding(DS.Space.xs)
                }
                .onChange(of: highlighted) {
                    proxy.scrollTo(highlighted)
                }
            }
        }
    }

    private func button(_ item: Item, at index: Int) -> some View {
        let isHighlighted = index == highlighted
        return Button {
            onChoose(item)
        } label: {
            row(item, isHighlighted)
                .padding(.horizontal, DS.Space.lg)
                .frame(height: DS.Size.listRow)
                .background(isHighlighted ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { highlighted = index }
        }
    }
}
