#if DEBUG
import Foundation
import Terminal

enum TerminalLogPreviewFixtures {
    static var running: TerminalLog {
        let log = TerminalLog(
            job: TerminalJob(key: "preview", name: "After creating a worktree", command: "pnpm install"))
        log.output = "$ pnpm install\nInstalling dependencies…\n"
        return log
    }

    static var failed: TerminalLog {
        let log = running
        log.job.finish(status: 1, duration: .seconds(3))
        log.output += "Could not reach the package registry.\n"
        log.detail = "The task can continue. Retry when the registry is available."
        return log
    }
}
#endif
