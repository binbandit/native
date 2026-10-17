import Observation

#if os(macOS)
import AppKit
#endif

/// Samples Native's and its agents' processes every few seconds while the status bar's item is on
/// screen, keeping a short history for sparklines.
@Observable
final class ResourceMonitor {
    private(set) var snapshot = ResourceSnapshot.empty
    /// Each group's memory over the last `historyLength` samples, oldest first.
    private(set) var history: [ProcessGroup.Kind: [UInt64]] = [:]
    /// The total's memory over the same samples.
    private(set) var totalHistory: [UInt64] = []

    /// Often enough for a live feel; each sample costs about a millisecond off the main actor.
    static let interval = Duration.seconds(3)
    /// Three minutes at the sampling interval.
    static let historyLength = 60

    @ObservationIgnored private let sampler: any ResourceSampling
    @ObservationIgnored private let isVisible: @MainActor () -> Bool

    /// - Parameters:
    ///   - sampler: Where the numbers come from: this Mac's processes, or later, a host's.
    ///   - isVisible: Whether anyone could see the numbers now; sampling pauses while not.
    init(sampler: any ResourceSampling = ProcessSampler(), isVisible: @escaping @MainActor () -> Bool = ResourceMonitor.isAppVisible) {
        self.sampler = sampler
        self.isVisible = isVisible
    }

    /// Samples until the calling task is cancelled, which happens when the item leaves the screen
    /// (hidden from the bar, or the bar's window closed).
    func run(roots: @escaping @MainActor () -> [ProcessSampler.Root]) async {
        while !Task.isCancelled {
            if isVisible() {
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

    /// No numbers for a hidden, minimized or fully covered app.
    static func isAppVisible() -> Bool {
        #if os(macOS)
        NSApplication.shared.occlusionState.contains(.visible)
        #else
        true
        #endif
    }
}
