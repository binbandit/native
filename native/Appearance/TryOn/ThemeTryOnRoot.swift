import SwiftUI

extension View {
    /// Try On's part of the main window: it ends when the user goes to another task or opens Settings,
    /// or presses Escape or ⌘. anywhere in the window, and it shows the sidebar's column while it runs,
    /// putting the sidebar back as it was afterwards.
    func themeTryOnRoot(
        sidebar: Binding<NavigationSplitViewVisibility>, selection: SessionKey?, isSettingsShown: Bool
    ) -> some View {
        modifier(ThemeTryOnRootModifier(sidebar: sidebar, selection: selection, isSettingsShown: isSettingsShown))
    }
}

private struct ThemeTryOnRootModifier: ViewModifier {
    @Binding var sidebar: NavigationSplitViewVisibility
    let selection: SessionKey?
    let isSettingsShown: Bool
    @Environment(ThemeTryOnModel.self) private var tryOn: ThemeTryOnModel?
    /// The sidebar as the user had it before Try On showed its panel there.
    @State private var sidebarBeforeTryOn: NavigationSplitViewVisibility?

    func body(content: Content) -> some View {
        content
            .onChange(of: selection) { _, key in
                // Going to another task ends Try On there.
                if let stage = tryOn?.stage, stage != key.map(ThemeTryOnModel.Stage.task) { tryOn?.abandon() }
            }
            .onChange(of: isSettingsShown) { _, shown in
                if shown { tryOn?.abandon() }
            }
            .onChange(of: tryOn?.isLockedByPolicy == true) { _, locked in
                if locked { tryOn?.policyChanged() }
            }
            // Escape and ⌘. end Try On from anywhere in the window, never stopping the task's turn.
            .windowCancelKeys(enabled: tryOn?.isActive == true) { tryOn?.cancel() }
            .onChange(of: tryOn?.isActive == true) { _, trying in
                if trying {
                    sidebarBeforeTryOn = sidebar
                    sidebar = .all
                } else if let visibility = sidebarBeforeTryOn {
                    sidebar = visibility
                    sidebarBeforeTryOn = nil
                }
            }
    }
}

/// The sidebar's column: Try On's panel while it runs. The sidebar stays underneath, so its scroll
/// position and picks are there afterwards.
struct ThemeTryOnSidebar<Sidebar: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @Environment(ThemeTryOnModel.self) private var tryOn: ThemeTryOnModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isTryingOn = tryOn?.isActive == true
        ZStack {
            sidebar
                .opacity(isTryingOn ? 0 : 1)
                .disabled(isTryingOn)
                .accessibilityHidden(isTryingOn)
            if let tryOn, isTryingOn {
                ThemeTryOnPanel(tryOn: tryOn)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .dsPanel, value: isTryingOn)
    }
}

/// The detail column, or the sample task while Try On shows the themes on it.
struct ThemeTryOnDetail<Detail: View>: View {
    @ViewBuilder let detail: Detail
    @Environment(ThemeTryOnModel.self) private var tryOn: ThemeTryOnModel?

    var body: some View {
        if tryOn?.stage == .sample {
            ThemeTryOnSampleTask()
        } else {
            detail
        }
    }
}
