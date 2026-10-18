import SwiftUI

extension FocusedValues {
    /// Whether the main window shows the pull requests page; published by the root view so Go ▸
    /// Pull Requests (`go.pullRequests`, ⌘⇧P) can open it.
    @Entry var showsPullRequests: Binding<Bool>?
}
