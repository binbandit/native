import SwiftUI

/// The slim bar along the window's bottom edge, after the reference app's footer: registered items at each end
/// on one line, leading ones clipping first when the window is narrow. Right-click shows or hides
/// items. Put it under the window's content in a VStack, so it's part of the layout; hidden or
/// with no items, it takes no space.
struct StatusBar: View {
    let registry: StatusBarRegistry

    var body: some View {
        if registry.isVisible {
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: StatusBarMetrics.segmentSpacing) {
            segments(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            segments(.trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, StatusBarMetrics.edgeInset - DS.Space.xs)
        .frame(maxWidth: .infinity)
        .frame(height: StatusBarMetrics.height)
        .background(.dsSurfaceSunken)
        .overlay(alignment: .top) { SeparatorLine() }
        .contextMenu { visibilityMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar")
    }

    private func segments(_ placement: StatusBarPlacement) -> some View {
        HStack(spacing: StatusBarMetrics.segmentSpacing) {
            ForEach(registry.visibleItems(placement)) { item in
                item.content
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var visibilityMenu: some View {
        Section("Show in Status Bar") {
            ForEach(registry.orderedItems) { item in
                Toggle(item.title, isOn: Binding {
                    registry.isVisible(item.id)
                } set: {
                    registry.setVisible($0, for: item.id)
                })
            }
        }
        Button("Hide Status Bar") {
            registry.isShown = false
        }
    }
}
