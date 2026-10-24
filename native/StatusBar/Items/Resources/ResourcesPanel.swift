import SwiftUI

/// Every process tree's memory and CPU with its trend, and on expanding a tree, each process in it
/// as a table. Columns sort by clicking their headers.
struct ResourcesPanel: View {
    let monitor: ResourceMonitor

    @Environment(\.openURL) private var openURL
    @State private var sort = ResourceSort.memory
    @State private var expanded: Set<ProcessGroup.Kind>

    init(monitor: ResourceMonitor, expanded: Set<ProcessGroup.Kind> = []) {
        self.monitor = monitor
        _expanded = State(initialValue: expanded)
    }

    private var snapshot: ResourceSnapshot {
        monitor.snapshot
    }

    var body: some View {
        PopoverPanel(title: "Memory and CPU", systemImage: "memorychip") {
            #if os(macOS)
            IconButton("Open Activity Monitor", systemImage: "arrow.up.forward.app") {
                openURL(URL(filePath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            #endif
        } content: {
            summary
            SeparatorLine()
            ResourceTableHeader(sort: $sort)
            SeparatorLine()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sort.ordered(snapshot.groups)) { group in
                        ResourceGroupRows(
                            group: group,
                            history: monitor.history[group.kind] ?? [],
                            isExpanded: Binding {
                                expanded.contains(group.kind)
                            } set: {
                                if $0 { expanded.insert(group.kind) } else { expanded.remove(group.kind) }
                            }
                        )
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
            .frame(maxHeight: StatusBarMetrics.panelListHeight)
            .fixedSize(horizontal: false, vertical: true)
            PopoverPanelFootnote(
                "Memory is each process's footprint, as Activity Monitor shows it. CPU is a share of this Mac's total CPU capacity (0 to 100%). Updated every 3 seconds while this is open."
            )
        }
        .onAppear { monitor.setShowingDetails(true) }
        .onDisappear { monitor.setShowingDetails(false) }
    }

    /// The summary line: total CPU and memory, with the total's trend.
    private var summary: some View {
        HStack(spacing: DS.Space.md) {
            Text(DSFormat.cpu(snapshot.cpu))
                .foregroundStyle(.dsTextPrimary)
            StatusBarDivider()
            Text(DSFormat.memory(snapshot.memory))
                .foregroundStyle(.dsTextPrimary)
            Text("in \(snapshot.processCount) \(snapshot.processCount == 1 ? "process" : "processes")")
                .foregroundStyle(.dsTextTertiary)
            Spacer(minLength: DS.Space.md)
            Sparkline(values: monitor.totalHistory)
        }
        .font(.dsBody)
        .monospacedDigit()
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlSM)
        .accessibilityElement(children: .combine)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Memory and CPU panel - Machine share") {
    ResourcesPanelPreview()
}

/// The panel with every group closed, and with Claude Code's open to its processes.
private struct ResourcesPanelPreview: View {
    private let monitor = StatusBarPreviewFixtures.monitor()

    var body: some View {
        DSPreviewPair {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                ResourcesPanel(monitor: monitor)
                ResourcesPanel(monitor: monitor, expanded: [.agent("claude-code")])
            }
            .dsPopoverBackground()
        }
        .task { await StatusBarPreviewFixtures.fill(monitor) }
    }
}
#endif
