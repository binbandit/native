import SwiftUI

/// The bar along the window's bottom edge, after the reference app's footer: registered items at each end of a
/// `StatusBarSurface`, which drops the innermost ones whole when the window is narrow.
/// Right-click shows or hides items. Put it under the window's content in a VStack, so it's part
/// of the layout; hidden or with no items, it takes no space.
struct StatusBar: View {
    let registry: StatusBarRegistry

    var body: some View {
        if registry.isVisible {
            bar
        }
    }

    private var bar: some View {
        StatusBarSurface {
            items(.leading)
        } trailing: {
            items(.trailing)
        }
        .contextMenu { visibilityMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar")
    }

    private func items(_ placement: StatusBarPlacement) -> some View {
        ForEach(registry.visibleItems(placement)) { item in
            item.content
        }
    }

    @ViewBuilder
    private var visibilityMenu: some View {
        Section("Show in Status Bar") {
            ForEach(registry.orderedItems) { item in
                Toggle(
                    item.title,
                    isOn: Binding {
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
