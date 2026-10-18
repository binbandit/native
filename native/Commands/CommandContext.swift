import SwiftUI

/// What a command acts on: the frontmost window's task and the window state its views publish as
/// focused scene values. The menu bar reads it live; the palette reads it when it opens.
@MainActor
struct CommandContext {
    /// The task in the window's detail column, if one is showing.
    var session: SessionModel?
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>?
    var needsYouFilter: Binding<Bool>?
    var mcpServersPopover: Binding<Bool>?
    var changesInspector: Binding<Bool>?
    var pullRequestsPage: Binding<Bool>?
    var jumpToLatest: TranscriptJumpCommand?
    /// Brings the main window back (it may be closed while the menu bar still works).
    var openMainWindow: @MainActor () -> Void = {}

    /// The window's undo manager, so ⌘Z takes back what a command did.
    var undoManager: UndoManager? {
        PlatformWindow.keyUndoManager
    }
}

/// Reads a `CommandContext` from the focused scene, in a view or in the menu bar's commands.
@MainActor
@propertyWrapper
struct FocusedCommandContext: DynamicProperty {
    @FocusedValue(\.activeSession) private var session
    @FocusedValue(\.sidebarVisibility) private var sidebarVisibility
    @FocusedValue(\.sidebarNeedsYouFilter) private var needsYouFilter
    @FocusedValue(\.mcpServersPopover) private var mcpServersPopover
    @FocusedValue(\.gitChangesInspector) private var changesInspector
    @FocusedValue(\.showsPullRequests) private var pullRequestsPage
    @FocusedValue(\.transcriptJumpToLatest) private var jumpToLatest
    @Environment(\.openWindow) private var openWindow

    var wrappedValue: CommandContext {
        CommandContext(
            session: session,
            sidebarVisibility: sidebarVisibility,
            needsYouFilter: needsYouFilter,
            mcpServersPopover: mcpServersPopover,
            changesInspector: changesInspector,
            pullRequestsPage: pullRequestsPage,
            jumpToLatest: jumpToLatest,
            openMainWindow: { [openWindow] in openWindow(id: NativeWindowID.main) }
        )
    }
}

/// The scenes' ids, for commands that bring a window back.
enum NativeWindowID {
    static let main = "main"
}
