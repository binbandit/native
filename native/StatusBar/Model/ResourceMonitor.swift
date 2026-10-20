import Observation

#if os(macOS)
import AppKit
#endif

/// Samples Native's and its agents' processes while the status bar's item is on screen, keeping a
/// short history for sparklines. It samples often only while something happens (a task works, or
/// the details are open); an idle app's figures barely move, so then it samples rarely, and the
/// bar redraws only when a figure it shows changes.
@Observable
final class ResourceMonitor {
    /// What the bar shows. Assigned only when it changes.
    private(set) var reading = ResourceReading.measuring
    /// The latest sample, for the details.
    private(set) var snapshot = ResourceSnapshot.empty
    /// Each group's memory over the last `historyLength` samples, oldest first.
    private(set) var history: [ProcessGroup.Kind: [UInt64]] = [:]
    /// The total's memory over the same samples.
    private(set) var totalHistory: [UInt64] = []
    /// Whether the details are open, which samples at the busy pace. Nothing draws from it.
    private(set) var isShowingDetails = false

    /// While a task works or the details are open: often enough for a live feel. Each sample costs
    /// about a millisecond off the main actor, plus redrawing what changed.
    static let interval = Duration.seconds(3)
    /// While nothing works: an idle app's figures barely move. A task starting, an agent starting
    /// or stopping, or the details opening samples at once.
    static let idleInterval = Duration.seconds(30)
    /// The last 60 samples: three minutes while something works, longer while idle.
    static let historyLength = 60

    @ObservationIgnored private let sampler: any ResourceSampling
    @ObservationIgnored private let isVisible: @MainActor () -> Bool

    /// - Parameters:
    ///   - sampler: Where the numbers come from: this Mac's processes, or later, a host's.
    ///   - isVisible: Whether anyone could see the numbers now; sampling pauses while not.
    init(
        sampler: any ResourceSampling = ProcessSampler(),
        isVisible: @escaping @MainActor () -> Bool = ResourceMonitor.isAppVisible
    ) {
        self.sampler = sampler
        self.isVisible = isVisible
    }

    /// What decides how often to sample, and what a change in samples at once.
    private struct Activity: Equatable, Sendable {
        let roots: [ProcessSampler.Root]
        let isWorking: Bool
        let isShowingDetails: Bool

        var interval: Duration {
            isWorking || isShowingDetails ? ResourceMonitor.interval : ResourceMonitor.idleInterval
        }
    }

    /// Samples until the calling task is cancelled, which happens when the item leaves the screen
    /// (hidden from the bar, or the bar's window closed). While nobody could see the numbers it
    /// sleeps until that changes, rather than checking every few seconds.
    ///
    /// - Parameters:
    ///   - roots: The running agents' processes.
    ///   - isWorking: Whether any task is working, which samples at the busy pace.
    func run(
        roots: @escaping @MainActor () -> [ProcessSampler.Root], isWorking: @escaping @MainActor () -> Bool
    )
        async
    {
        let activity: @MainActor () -> Activity = { [weak self] in
            Activity(roots: roots(), isWorking: isWorking(), isShowingDetails: self?.isShowingDetails ?? false)
        }
        // The first sample's CPU covers launch itself, so the next comes soon rather than leaving a
        // launch-time figure on the bar for the whole idle interval.
        var isFirstSample = true
        while !Task.isCancelled {
            if isVisible() {
                let current = activity()
                await sample(roots: current.roots)
                let wait = isFirstSample ? Self.interval : current.interval
                isFirstSample = false
                await Self.pause(for: wait, orUntilChanged: current, in: activity)
            } else {
                await Self.visibilityChange()
            }
        }
    }

    /// The details opened or closed: sample at once, then at the pace that fits.
    func setShowingDetails(_ isShowing: Bool) {
        isShowingDetails = isShowing
    }

    /// Returns after `duration`, or as soon as `activity` reads something other than `current`.
    private static func pause(
        for duration: Duration, orUntilChanged current: Activity, in activity: @escaping @MainActor () -> Activity
    ) async {
        let sleep = Task {
            try? await Task.sleep(for: duration, tolerance: duration / 10)
        }
        let watch = Task {
            for await next in Observations(activity) where next != current {
                break
            }
            sleep.cancel()
        }
        await withTaskCancellationHandler {
            await sleep.value
        } onCancel: {
            sleep.cancel()
        }
        watch.cancel()
    }

    /// Returns when the app is shown, hidden, minimized or uncovered, or the calling task is cancelled.
    private static func visibilityChange() async {
        #if os(macOS)
        let changes = NotificationCenter.default.notifications(named: NSApplication.didChangeOcclusionStateNotification)
        for await _ in changes { return }
        #else
        try? await Task.sleep(for: interval)
        #endif
    }

    /// Takes a sample now.
    func sample(roots: [ProcessSampler.Root]) async {
        let snapshot = await sampler.sample(agents: roots)
        self.snapshot = snapshot
        let reading = ResourceReading(snapshot)
        if reading != self.reading {
            self.reading = reading
        }
        var history: [ProcessGroup.Kind: [UInt64]] = [:]
        for group in snapshot.groups {
            history[group.kind] = Array(
                (self.history[group.kind, default: []] + [group.memory]).suffix(Self.historyLength))
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
