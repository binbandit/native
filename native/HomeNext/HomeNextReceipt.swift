import Foundation

struct HomeNextReceipt {
    let task: SessionKey
    let title: String
    let action: String
    let date: Date
    /// A task started from the start field; its session replaces `task` once the agent opens it.
    var starting: StartingTask?
}
