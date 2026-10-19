import SwiftUI

/// Which end of the status bar an item sits at. Leading items give way first when the window is
/// narrow; trailing items never clip.
enum StatusBarPlacement: Sendable {
    case leading, trailing
}

/// Something the status bar shows. Features add items by registering them with
/// `StatusBarRegistry`, so the bar never lists them itself.
///
/// An item draws its own segment (usually a `StatusBarSegment` with a popover or a menu) and should
/// explain itself: a tooltip that says what it measures, and on click, the details.
protocol StatusBarItem {
    associatedtype Content: View

    /// Stable across launches: the bar remembers hidden items by it.
    var id: String { get }
    /// The item's name in the bar's show-and-hide menu.
    var title: String { get }
    var placement: StatusBarPlacement { get }
    /// Position within its end, low to high from left to right: the leading end from the window's
    /// edge inwards, the trailing end towards it. Built-in items use multiples of 10 so others can go
    /// between.
    var order: Int { get }

    @MainActor @ViewBuilder var content: Content { get }
}

/// A registered item with its view type erased, since items come from different features.
struct AnyStatusBarItem: Identifiable {
    let id: String
    let title: String
    let placement: StatusBarPlacement
    let order: Int
    private let makeContent: @MainActor () -> AnyView

    init(_ item: some StatusBarItem) {
        id = item.id
        title = item.title
        placement = item.placement
        order = item.order
        makeContent = { AnyView(item.content) }
    }

    @MainActor
    var content: AnyView {
        makeContent()
    }
}
