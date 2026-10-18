import Foundation

extension AppModel {
    /// What restarting Native would interrupt, for the updater (`UpdateController.restartContext`).
    var updateRestartContext: UpdateRestartContext {
        let working = agents.flatMap { sessions.open(of: $0.agent.id) }.filter { $0.phase == .prompting }.count
        // These agents run in the app, so a restart stops them; sessions the durable host runs keep
        // going and aren't counted (docs/durability.md).
        return UpdateRestartContext(workingTasks: working, keepsRunning: false)
    }
}
