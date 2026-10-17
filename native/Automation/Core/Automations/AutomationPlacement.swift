import Foundation

/// Where an automation's run works.
nonisolated enum AutomationPlacement: String, Codable, Hashable, Sendable, CaseIterable {
    /// A new worktree per run, so it never touches the user's own checkout.
    case worktree
    /// The project's folder as it is.
    case mainCheckout

    var label: String {
        switch self {
        case .worktree: "New worktree"
        case .mainCheckout: "Main checkout"
        }
    }
}
