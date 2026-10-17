/// What restarting Native would interrupt. The app supplies it (`UpdateController.restartContext`)
/// so the updater never reaches into session models.
struct UpdateRestartContext: Equatable, Sendable {
    /// Tasks with a turn running right now.
    var workingTasks: Int
    /// Whether those tasks keep running through a restart: true when the durable host owns them.
    var keepsRunning: Bool

    static let idle = UpdateRestartContext(workingTasks: 0, keepsRunning: true)

    /// A restart would stop work in progress, so ask first.
    var needsConfirmation: Bool { workingTasks > 0 && !keepsRunning }

    /// One line for the restart button's help and the Updates page.
    var summary: String? {
        guard workingTasks > 0 else { return nil }
        let tasks = workingTasks == 1 ? "Your working task" : "Your \(workingTasks) working tasks"
        let keep = workingTasks == 1 ? "keeps" : "keep"
        return keepsRunning ? "\(tasks) \(keep) running while Native restarts." : "\(tasks) will stop if Native restarts now."
    }
}
