import Foundation

/// Reported worker details and the checkout they work in, kept separate from the activity headline.
struct TaskWellIdentity {
    var model: String?
    var machine: String
    var timing: String?
    var contextFraction: Double?
    var isManaged = false
    var management: String?
    /// The task's project by name, never its worktree folder, and its branch.
    var project = ""
    var branch: String?
}
