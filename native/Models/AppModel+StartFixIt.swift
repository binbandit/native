import Foundation
import NativeSetup

// Fix-its for a task that couldn't start (Fine print): the line the agent stopped at, and a
// one-click change to it. Only on this Mac, and only a settings file the agent's report names that
// isn't a credential store (`AgentStartFile.mayRead`).
extension AppModel {
    /// The lines around where the agent stopped, when it named a file on this Mac.
    func startFailureSource(of task: StartingTask) async -> [AgentStartDiagnostic.SourceLine] {
        guard task.device == .thisMac, let diagnostic = task.failure?.diagnostic else { return [] }
        let path = diagnostic.path
        let contents = await Task.detached { AgentStartFile.read(path) }.value
        return contents.map(diagnostic.excerpt) ?? []
    }

    /// The change Native can make for the task's failure; none for a file on another device or one
    /// Native may not open (`AgentStartFile.mayRead`).
    func startFixIt(for task: StartingTask) -> AgentStartFixIt? {
        guard task.device == .thisMac, let diagnostic = task.failure?.diagnostic,
            AgentStartFile.mayRead(diagnostic.path)
        else { return nil }
        return diagnostic.fixIt
    }

    /// Changes the value the agent rejected, keeping the original beside the file, then starts the
    /// task again with its message.
    func applyStartFixIt(to task: StartingTask) async throws(AgentStartFile.Failure) {
        guard let diagnostic = task.failure?.diagnostic, let fixIt = startFixIt(for: task) else { return }
        let applied = await Task.detached {
            Result { () throws(AgentStartFile.Failure) in try AgentStartFile.apply(fixIt, at: diagnostic) }
        }.value
        _ = try applied.get()
        await retry(task)
    }
}

extension StartingTask.Failure {
    /// Where the agent says it stopped, when its report names a file and line.
    var diagnostic: AgentStartDiagnostic? {
        AgentStartDiagnostic(output: message)
    }
}
