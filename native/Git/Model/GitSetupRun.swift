import Foundation
import Git

/// The setup of one task worktree: copying the project's ignored files, then its setup script.
struct GitSetupRun: Equatable {
    enum State: Equatable {
        case running
        case finished(SetupScriptResult)
        /// The script couldn't start, or the files couldn't be copied.
        case failed(String)
    }

    var state: State
    var copiedFiles: [String]
    /// Copying the ignored files failed; the script still ran.
    var copyFailure: String?
    /// The project's main checkout, whose setup script this is.
    let projectRoot: URL

    var isFailure: Bool {
        switch state {
        case .running: false
        case .finished(let result): !result.succeeded
        case .failed: true
        }
    }
}
