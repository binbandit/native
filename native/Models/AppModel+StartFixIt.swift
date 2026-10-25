import Foundation
import NativeSetup

// Fix-its for a task that couldn't start (Fine print): the line the agent stopped at, and a
// one-click change to it. Only on this Mac, and only a settings file the agent's plugin declares
// (`AgentManifest.settingsFiles`): the path in the agent's error authorizes nothing by itself.
extension AppModel {
    /// The lines around where the agent stopped, when it names one of its settings files.
    func startFailureSource(of task: StartingTask) async -> [AgentStartDiagnostic.SourceLine] {
        guard let diagnostic = task.failure?.diagnostic, let allowed = await settingsFiles(of: task),
            AgentStartFile.mayRead(diagnostic.path, allowed: allowed)
        else { return [] }
        let path = diagnostic.path
        let contents = await Task.detached { AgentStartFile.read(path, allowed: allowed) }.value
        return contents.map(diagnostic.excerpt) ?? []
    }

    /// The change Native can make for the task's failure: only in one of the agent's settings files
    /// on this Mac.
    func startFixIt(for task: StartingTask) async -> AgentStartFixIt? {
        guard let diagnostic = task.failure?.diagnostic, let allowed = await settingsFiles(of: task),
            AgentStartFile.mayRead(diagnostic.path, allowed: allowed)
        else { return nil }
        return diagnostic.fixIt
    }

    /// Changes the value the agent rejected, keeping the original beside the file, then starts the
    /// task again with its message.
    func applyStartFixIt(to task: StartingTask) async throws(AgentStartFile.Failure) {
        guard let diagnostic = task.failure?.diagnostic, let fixIt = await startFixIt(for: task),
            let allowed = await settingsFiles(of: task)
        else { return }
        let applied = await Task.detached {
            Result { () throws(AgentStartFile.Failure) in
                try AgentStartFile.apply(fixIt, at: diagnostic, allowed: allowed)
            }
        }.value
        _ = try applied.get()
        await retry(task)
    }

    /// The agent's declared settings files for the task, or nil for a task on another device.
    private func settingsFiles(of task: StartingTask) async -> [String]? {
        guard task.device == .thisMac else { return nil }
        let environment = await launchEnvironment().merging(task.agent.manifest.env) { $1 }
        return AgentStartFile.settingsPaths(
            task.agent.manifest.settingsFiles, home: NSHomeDirectory(), environment: environment,
            folder: task.folder?.path(percentEncoded: false))
    }
}

extension StartingTask.Failure {
    /// Where the agent says it stopped, when its report names a file and line.
    var diagnostic: AgentStartDiagnostic? {
        AgentStartDiagnostic(output: message)
    }
}
