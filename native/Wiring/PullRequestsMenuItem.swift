import SwiftUI

extension FocusedValues {
    /// Whether the main window shows the pull requests page; published by the root view so the Go
    /// menu's ⌘⇧P can open it.
    @Entry var showsPullRequests: Binding<Bool>?
}

/// "Pull Requests" for the Go menu (⇧⌘P, see `docs/keyboard.md`).
struct PullRequestsMenuItem: View {
    @FocusedValue(\.showsPullRequests) private var showsPullRequests

    var body: some View {
        Button("Pull Requests") {
            showsPullRequests?.wrappedValue = true
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(showsPullRequests == nil)
    }
}
