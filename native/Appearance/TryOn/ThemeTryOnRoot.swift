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
    @State private var windowWidth: CGFloat = 0
    /// Keeps Changes closed past the end of Try On until the sidebar has stepped aside again, so it
    /// comes back into the room it had.
    @State private var holdsInspectors = false
    @State private var room = PlatformWindowRoom()

    func body(content: Content) -> some View {
        let isTryingOn = tryOn?.isActive == true
        content
            // A narrow window can't hold the panel, the conversation and Changes side by side, so
            // Changes stays closed for the duration, from before the sidebar shows.
            // Asking for an inspector meanwhile ends Try On where the user is, writing nothing.
            .environment(
                \.inspectorSuspension,
                (isTryingOn && windowWidth < DS.TryOn.narrowWindowWidth) || holdsInspectors
                    ? InspectorSuspension { tryOn?.abandon() } : nil
            )
            // Read while Try On isn't running: the layout it changes mustn't feed back into whether
            // Changes fits, or the two would keep flipping each other.
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                if !isTryingOn, !holdsInspectors { windowWidth = width }
            }
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
            .windowCancelKeys(enabled: isTryingOn) { tryOn?.cancel() }
            .tracksWindowRoom(room)
            .onChange(of: isTryingOn) { _, trying in
                if trying {
                    holdsInspectors = windowWidth < DS.TryOn.narrowWindowWidth
                    sidebarBeforeTryOn = sidebar
                    // Once Changes has stepped aside (it counts toward the window's minimum until it
                    // has), so the sidebar has its room.
                    Task {
                        if holdsInspectors { await room.waitUntilSettled() }
                        await room.waitUntil { !room.wouldGrow(adding: DS.Window.sidebarMinWidth) }
                        if tryOn?.isActive == true { sidebar = .all }
                    }
                } else {
                    let withSidebar = room.minWidth
                    let hidesSidebar = sidebarBeforeTryOn == .detailOnly
                    if let visibility = sidebarBeforeTryOn { sidebar = visibility }
                    sidebarBeforeTryOn = nil
                    // Once the sidebar has stepped aside again (it counts toward the window's minimum
                    // until it has), so Changes comes back into the room it had.
                    Task {
                        if hidesSidebar {
                            await room.waitUntil { room.minWidth <= withSidebar - DS.Window.sidebarMinWidth }
                        }
                        holdsInspectors = false
                    }
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
