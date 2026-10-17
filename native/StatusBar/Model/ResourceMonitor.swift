import AppKit
import Observation

/// Samples Native's and its agents' processes every couple of seconds while the status bar is on
/// screen, keeping a short history for sparklines.
@Observable
final class ResourceMonitor {
    private(set) var snapshot = ResourceSnapshot.empty
    /// Each group's memory over the last `historyLength` samples, oldest first.
    private(set) var history: [ProcessGroup.Kind: [UInt64]] = [:]
    /// The total's memory over the same samples.
    private(set) var totalHistory: [UInt64] = []

    static let interval = Duration.seconds(2)
    /// Two minutes at the sampling interval.
    static let historyLength = 60

    @ObservationIgnored private let sampler = ProcessSampler()

    /// Samples until the calling task is cancelled. Sampling pauses while no Native window is
    /// visible (hidden, minimized or covered), where nobody would see the numbers.
    func run(roots: @escaping @MainActor () -> [ProcessSampler.Root]) async {
        while !Task.isCancelled {
            if NSApplication.shared.occlusionState.contains(.visible) {
                await sample(roots: roots())
            }
            try? await Task.sleep(for: Self.interval)
        }
    }

    /// Takes a sample now, such as when the details open.
    func sample(roots: [ProcessSampler.Root]) async {
        let snapshot = await sampler.sample(agents: roots)
        self.snapshot = snapshot
        var history: [ProcessGroup.Kind: [UInt64]] = [:]
        for group in snapshot.groups {
            history[group.kind] = Array((self.history[group.kind, default: []] + [group.memory]).suffix(Self.historyLength))
        }
        self.history = history
        totalHistory = Array((totalHistory + [snapshot.memory]).suffix(Self.historyLength))
    }
}
