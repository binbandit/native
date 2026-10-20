import SwiftUI

/// The bar along the window's bottom edge: registered items at each end of a
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

    /// The bar shows from the window's first frame, and its items from the frame after: they read
    /// and sample a good deal, and the first frame shouldn't wait for that.
    private func items(_ placement: StatusBarPlacement) -> some View {
        ForEach(FirstFrame.shared.isOnScreen ? registry.visibleItems(placement) : []) { item in
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

#if NATIVE_PREVIEWS_WIP
#Preview("Status bar") {
    StatusBarPreview(app: AppModel.preview(), limits: StatusBarPreviewFixtures.limits, width: 980)
}

#Preview("Status bar - Nothing running, no limits") {
    StatusBarPreview(app: AppModel.preview(.empty), limits: [], width: 980)
}

#Preview("Status bar - Narrow") {
    // Narrow windows drop the innermost items whole.
    StatusBarPreview(app: AppModel.preview(), limits: StatusBarPreviewFixtures.limits, width: 420)
}

/// The bar over its window's content, with the built-in items and sampled figures.
private struct StatusBarPreview: View {
    let app: AppModel
    let limits: [LimitStatus]
    let width: CGFloat
    private let monitor = StatusBarPreviewFixtures.monitor()

    var body: some View {
        DSPreviewPair {
            StatusBar(registry: StatusBarPreviewFixtures.registry(app, limits: limits, monitor: monitor))
                .frame(width: width)
        }
        .environment(CommandRegistry.shared)
        .task {
            // The bar fills in its items from the window's second frame.
            FirstFrame.shared.watch()
            await StatusBarPreviewFixtures.fill(monitor)
        }
    }
}
#endif
