import Foundation

/// The budget one script runs within. The runtime enforces its own fixed limits besides these:
/// 5 MiB of text in at most 1024 `text()` calls, 128 tool calls in flight and 1024 timers.
public struct ScriptLimits: Sendable, Hashable {
    /// Wall-clock time from launch; the runtime process is killed when it runs out.
    public var time: Duration
    /// V8's heap limit, 16 to 4096 MiB.
    public var heapMiB: Int
    /// Tool calls one script can make in total.
    public var toolCalls: Int
    /// The largest tool result handed to a script, as JSON text; larger results fail the call.
    public var toolResultBytes: Int

    public init(
        time: Duration = .seconds(60), heapMiB: Int = 128, toolCalls: Int = 1000, toolResultBytes: Int = 5 << 20
    ) {
        self.time = time
        self.heapMiB = heapMiB
        self.toolCalls = toolCalls
        self.toolResultBytes = toolResultBytes
    }

    public static let standard = ScriptLimits()
}
