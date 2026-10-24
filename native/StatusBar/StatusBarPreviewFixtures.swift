#if NATIVE_PREVIEWS_WIP
import Foundation
import SwiftUI

/// The status bar's previews: a registry with the built-in items over `AppModel.preview()`, and
/// memory figures from a sampler that reads no real process.
enum StatusBarPreviewFixtures {
    /// A monitor that never samples on its own: previews fill it with `fill(_:)`.
    static func monitor() -> ResourceMonitor {
        ResourceMonitor(sampler: PreviewResourceSampler(), isVisible: { false })
    }

    /// A few minutes of samples, so the figures and sparklines have something to show.
    static func fill(_ monitor: ResourceMonitor) async {
        for _ in 0..<24 {
            await monitor.sample(roots: [])
        }
    }

    static let limits: [LimitStatus] = [
        LimitStatus(
            id: "claude-code", provider: "Claude Code", level: .reached, window: "5-hour",
            resetsAt: .now.addingTimeInterval(42 * 60), utilization: 1, resume: .offered),
        LimitStatus(id: "codex", provider: "Codex", level: .warning, window: "weekly", utilization: 0.9),
    ]

    /// The bar as the app registers it, minus the items other features add.
    static func registry(_ app: AppModel, limits: [LimitStatus] = limits, monitor: ResourceMonitor) -> StatusBarRegistry
    {
        let registry = StatusBarRegistry(defaults: PreviewUserDefaults())
        registry.register(LimitsStatusItem(statuses: { limits }))
        registry.register(TasksStatusItem(source: app))
        registry.register(ResourcesStatusItem(source: app, monitor: monitor))
        registry.register(HelpStatusItem(help: KeyboardShortcutsHelp()))
        return registry
    }
}

/// Native, two agents and a shell, with memory that drifts a little from one sample to the next.
nonisolated final class PreviewResourceSampler: ResourceSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func sample(agents: [ProcessSampler.Root]) async -> ResourceSnapshot {
        let step = lock.withLock {
            count += 1
            return count
        }
        let drift = UInt64((step * 7) % 11) * 3_000_000
        let mb: UInt64 = 1_000_000
        return ResourceSnapshot(
            date: .now,
            groups: [
                ProcessGroup(
                    kind: .app, title: "Native",
                    processes: [
                        ProcessUsage(pid: 4012, name: "Native", depth: 0, memory: 212 * mb + drift, cpu: 0.175),
                        ProcessUsage(pid: 4018, name: "Native Host", depth: 1, memory: 38 * mb, cpu: 0.025),
                    ]),
                ProcessGroup(
                    kind: .agent("claude-code"), title: "Claude Code",
                    processes: [
                        ProcessUsage(pid: 5120, name: "claude-agent-acp", depth: 0, memory: 96 * mb, cpu: 0.1),
                        ProcessUsage(pid: 5131, name: "claude", depth: 1, memory: 610 * mb + drift * 2, cpu: 1.5625),
                        // 395% of one core on an eight-core machine becomes 49% in every resource view.
                        ProcessUsage(pid: 5190, name: "swift-frontend", depth: 2, memory: 1_840 * mb, cpu: 49.375),
                    ]),
                ProcessGroup(
                    kind: .agent("codex"), title: "Codex",
                    processes: [
                        ProcessUsage(pid: 6201, name: "codex-acp", depth: 0, memory: 54 * mb, cpu: 0.0125),
                        ProcessUsage(pid: 6214, name: "codex", depth: 1, memory: 188 * mb, cpu: nil),
                    ]),
                ProcessGroup(
                    kind: .other, title: "Other",
                    processes: [ProcessUsage(pid: 7001, name: "zsh", depth: 0, memory: 6 * mb, cpu: 0)]),
            ])
    }
}
#endif
