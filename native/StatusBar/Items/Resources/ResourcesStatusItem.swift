import SwiftUI

/// The memory and CPU Native and its agents use: Native's own and its agents' figures in the bar,
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

    /// Only the reading: the full sample changes on every one, the reading only when a figure does.
    private var reading: ResourceReading {
        monitor.reading
    }

    var body: some View {
        StatusBarSegment(
            help: "\(reading.summary) Click for each process.",
            accessibilityLabel: "Memory and CPU",
            accessibilityValue: reading.summary
        ) {
            HStack(spacing: DS.Space.sm) {
                StatusBarGlyph("memorychip")
                    .modifier(Tint(color: pressureTint))
                figures("Native", reading.app)
                if let agents = reading.agents {
                    StatusBarDivider()
                    figures("Agents", agents)
                }
            }
        } details: {
            ResourcesPanel(monitor: monitor)
        }
        .task {
            await monitor.run(
                roots: { source.statusBarAgentProcesses },
                isWorking: { source.statusBarTasks.contains { $0.status == .working } })
        }
    }

    /// "Native 104 MB 0.3%": whose, then memory and CPU.
    private func figures(_ title: String, _ figures: ResourceReading.Figures) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(title)
                .foregroundStyle(.dsTextTertiary)
            Text(figures.memory)
            Text(figures.cpu)
        }
    }

    /// Tints the glyph as memory gets tight: past a quarter and half of the Mac's RAM.
    private var pressureTint: Color? {
        switch reading.pressure {
        case .normal: nil
        case .high: .dsWarning
        case .critical: .dsDanger
        }
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

#if NATIVE_PREVIEWS_WIP
#Preview("Memory and CPU item") {
    ResourcesItemPreview()
}

/// The item before its first sample ("measuring"), and with a few minutes of samples.
private struct ResourcesItemPreview: View {
    private let app = AppModel.preview()
    private let measuring = StatusBarPreviewFixtures.monitor()
    private let sampled = StatusBarPreviewFixtures.monitor()

    var body: some View {
        DSPreviewPair {
            StatusBarSurface {
                EmptyView()
            } trailing: {
                ResourcesStatusItem(source: app, monitor: measuring).content
                ResourcesStatusItem(source: app, monitor: sampled).content
            }
            .frame(width: 520)
        }
        .task { await StatusBarPreviewFixtures.fill(sampled) }
    }
}
#endif
