import Exec
import NativeHostClient

extension SessionModel {
    /// Feature actions for this task must run on the same host, with that host's environment.
    func commandRunner() throws -> any CommandRunner {
        guard let host else {
            throw CommandError.unavailable("This task isn't connected to its host. Reopen it and try again.")
        }
        return RemoteCommandRunner(client: host.client)
    }
}
