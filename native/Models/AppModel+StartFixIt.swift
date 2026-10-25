import Foundation
import NativeSetup

// Fix-its for a task that couldn't start (Fine print): the line the agent stopped at, and a
// one-click change to it. Only on this Mac, and only a settings file the agent's plugin declares
// (`AgentManifest.settingsFiles`): a path in the agent's error authorizes nothing by itself.
extension AppModel {
    /// Where a failed start stopped, the lines there, and the change Native can offer.
    nonisolated struct StartFailureDetail: Equatable, Sendable {
        var diagnostic: AgentStartDiagnostic?
        var source: [AgentStartDiagnostic.SourceLine] = []
        var fixIt: AgentStartFixIt?
    }

    /// The location the agent's report names, or, when it names only the setting, the one line of
    /// its declared settings files that sets it; with the lines and fix-it when the file may be read.
    func startFailureDetail(of task: StartingTask) async -> StartFailureDetail {
        guard let failure = task.failure else { return StartFailureDetail() }
        let named = AgentStartDiagnostic(output: failure.message)
        guard let allowed = await settingsFiles(of: task) else { return StartFailureDetail(diagnostic: named) }
        let message = failure.message
        return await Task.detached {
            if let named {
                guard let contents = AgentStartFile.read(named.path, allowed: allowed) else {
                    return StartFailureDetail(diagnostic: named)
                }
                return StartFailureDetail(diagnostic: named, source: named.excerpt(of: contents), fixIt: named.fixIt)
            }
            let files = allowed.compactMap { path in AgentStartFile.read(path, allowed: allowed).map { (path, $0) } }
            guard let located = AgentStartDiagnostic(locating: message, in: files),
                let contents = files.first(where: { $0.0 == located.path })?.1
            else { return StartFailureDetail() }
            return StartFailureDetail(diagnostic: located, source: located.excerpt(of: contents), fixIt: located.fixIt)
        }.value
    }

    /// Changes the value the agent rejected, keeping the original beside the file, then starts the
    /// task again with its message.
    func applyStartFixIt(
        _ fixIt: AgentStartFixIt, at diagnostic: AgentStartDiagnostic, to task: StartingTask
    ) async throws(AgentStartFile.Failure) {
        guard let allowed = await settingsFiles(of: task) else { return }
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
