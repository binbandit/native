import Foundation
import Observation
import Terminal

/// A command already owned by a host-side runner. Its capped output and status share the task's
/// terminal tabs with interactive shells, without starting a second process or terminal engine.
@Observable
final class TerminalLog {
    var job: TerminalJob
    var output = ""
    var detail: String?
    @ObservationIgnored var retry: () -> Void = {}
    @ObservationIgnored var stop: () -> Void = {}
    @ObservationIgnored var changed: () -> Void = {}

    init(job: TerminalJob) {
        self.job = job
    }
}
