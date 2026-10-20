import Foundation
import SwiftUI

#if DEBUG
/// Which sidebar to show: a DEBUG-only prototype for choosing a direction, picked with
/// `-sidebarDesign a|b|c|d`. Without the argument the sidebar is today's.
enum SidebarDesign: String, CaseIterable {
    /// Organized by whose move it is, across projects: Your move, Running, Recent.
    case triage = "a"
    /// Today's projects tree, with marks only where something is happening.
    case quietProjects = "b"
    /// A rail of projects and live marks that expands into a keyboard navigator.
    case rail = "c"
    /// What happened, in order: a timeline of every task's latest event.
    case timeline = "d"

    /// The direction this launch asked for, if any.
    static let launchChoice: Self? = UserDefaults.standard.string(forKey: "sidebarDesign").flatMap(Self.init(rawValue:))

    /// Whether the rail replaces the sidebar column, which then has no room for the column's toolbar.
    static var isRail: Bool { launchChoice == .rail }
}

/// The rail's width and whether its navigator is open. One for the app, since the split view's column
/// width (in `RootView`) and the rail inside it both read it. `-sidebarDesignExpanded YES` opens it at
/// launch.
@Observable
final class SidebarDesignRailState {
    static let shared = SidebarDesignRailState()

    var isExpanded = UserDefaults.standard.bool(forKey: "sidebarDesignExpanded")

    /// The rail clears the window controls above it.
    static let railWidth: CGFloat = 76
    static let navigatorWidth: CGFloat = 272

    var columnWidth: CGFloat {
        Self.railWidth + (isExpanded ? Self.navigatorWidth : 0)
    }
}

#endif

extension View {
    /// The sidebar column's width: today's, or in DEBUG the `-sidebarDesign` rail's own.
    func sidebarColumnWidth(ideal: CGFloat) -> some View {
        modifier(SidebarColumnWidth(ideal: ideal))
    }
}

private struct SidebarColumnWidth: ViewModifier {
    let ideal: CGFloat

    func body(content: Content) -> some View {
        #if DEBUG
        if SidebarDesign.isRail {
            let rail = SidebarDesignRailState.shared
            content
                .navigationSplitViewColumnWidth(rail.columnWidth)
                .animation(.dsPanel, value: rail.isExpanded)
        } else if SidebarDesignFixture.launchChoice != nil {
            // Captures compare every sidebar at today's default width.
            content.navigationSplitViewColumnWidth(DS.Size.sidebarWidth)
        } else {
            today(content)
        }
        #else
        today(content)
        #endif
    }

    private func today(_ content: Content) -> some View {
        content
            .platformMinimumContentWidth(DS.Window.sidebarMinWidth)
            .navigationSplitViewColumnWidth(min: DS.Window.sidebarMinWidth, ideal: ideal, max: 380)
    }
}
