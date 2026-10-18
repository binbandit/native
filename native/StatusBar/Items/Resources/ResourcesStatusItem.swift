import SwiftUI

/// The memory and CPU Native and its agents use: the totals in the bar,
/// each process tree and process on click. Samples only while the bar is on screen.
struct ResourcesStatusItem: StatusBarItem {
    let source: any StatusBarSource
    let monitor: ResourceMonitor

    init(source: any StatusBarSource, monitor: ResourceMonitor = ResourceMonitor()) {
        self.source = source
        self.monitor = monitor
    }

    let id = "resources"
    let title = "Memory and CPU"
    let placement = StatusBarPlacement.trailing
    let order = 20

    var content: some View {
        ResourcesSegment(source: source, monitor: monitor)
    }
}

private struct ResourcesSegment: View {
    let source: any StatusBarSource
    let monitor: ResourceMonitor

    private var snapshot: ResourceSnapshot {
        monitor.snapshot
    }

    private var hasSample: Bool {
        snapshot.date != .distantPast
    }

    private var summary: String {
        guard hasSample else { return "Measuring…" }
        return "\(DSFormat.memory(snapshot.memory)) of memory (\(Self.shareOfPhysicalMemory(snapshot.memory))) and \(DSFormat.cpu(snapshot.cpu)) CPU"
    }

    var body: some View {
        StatusBarSegment(
            help: "Native and its agents are using \(summary). Click for each process.",
            accessibilityLabel: "Memory and CPU",
            accessibilityValue: summary,
            onOpen: { Task { await monitor.sample(roots: source.statusBarAgentProcesses) } }
        ) {
            HStack(spacing: DS.Space.sm) {
                StatusBarGlyph("memorychip")
                Text(hasSample ? DSFormat.memory(snapshot.memory) : "–")
                    .modifier(Tint(color: memoryTint))
                StatusBarDivider()
                StatusBarGlyph("cpu")
                Text(hasSample ? DSFormat.cpu(snapshot.cpu) : "–")
            }
        } details: {
            ResourcesPanel(monitor: monitor)
        }
        .task {
            await monitor.run { source.statusBarAgentProcesses }
        }
    }

    /// "6.7% of 48 GB": the memory against this Mac's.
    private static func shareOfPhysicalMemory(_ bytes: UInt64) -> String {
        let total = ProcessInfo.processInfo.physicalMemory
        return "\(DSFormat.share(Int(clamping: bytes), of: Int(clamping: total))) of \(DSFormat.memory(total))"
    }

    /// Tints the figure as memory gets tight: past a quarter and half of the Mac's RAM.
    private var memoryTint: Color? {
        let share = Double(snapshot.memory) / Double(max(ProcessInfo.processInfo.physicalMemory, 1))
        return share >= 0.5 ? .dsDanger : share >= 0.25 ? .dsWarning : nil
    }
}

/// Colors a figure when there's a reason to, and otherwise leaves the segment's own color.
private struct Tint: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}
