import Foundation
import ScriptRuntime
import Synchronization

/// Tools another feature binds into `run_script` for one session, such as the MCP servers set to
/// run through scripts. Asked on every listing and run, so what's bound follows the calling
/// session's project and what it may do.
nonisolated protocol OrchestrationScriptBindings: Sendable {
    /// What `caller`'s scripts can reach from here, for run_script's description; nil for nothing.
    func summary(for caller: OrchestrationCaller) async -> OrchestrationScriptSummary?
    /// Tools for one run, which has until `deadline` (tools waiting on the user give up by then).
    func bindings(for caller: OrchestrationCaller, until deadline: ContinuousClock.Instant) async -> [ScriptBinding]
}

nonisolated struct OrchestrationScriptSummary: Sendable {
    /// Names what's bound, such as "tools.rea.* (170 tools of the rea MCP server)".
    var description: String
    /// Whether every tool it binds is read-only; run_script is annotated read-only only while all are.
    var isReadOnly: Bool
}

/// The features binding tools into `run_script`, registered once the app is up.
nonisolated final class OrchestrationScriptExtensions: Sendable {
    private let sources = Mutex<[any OrchestrationScriptBindings]>([])

    func add(_ source: any OrchestrationScriptBindings) {
        sources.withLock { $0.append(source) }
    }

    func summaries(for caller: OrchestrationCaller) async -> [OrchestrationScriptSummary] {
        var summaries: [OrchestrationScriptSummary] = []
        for source in sources.withLock({ $0 }) {
            if let summary = await source.summary(for: caller) { summaries.append(summary) }
        }
        return summaries
    }

    func bindings(for caller: OrchestrationCaller, until deadline: ContinuousClock.Instant) async -> [ScriptBinding] {
        var bindings: [ScriptBinding] = []
        for source in sources.withLock({ $0 }) { bindings += await source.bindings(for: caller, until: deadline) }
        return bindings
    }
}
