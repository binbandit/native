import AppKit
import SwiftUI

/// Every process tree's memory and CPU with its trend, and on expanding a tree, each process in it
/// (the reference app's Resource Manager table). Columns sort by clicking their headers.
struct ResourcesPanel: View {
    let monitor: ResourceMonitor

    @State private var sort = ResourceSort.memory
    @State private var expanded: Set<ProcessGroup.Kind> = []

    private var snapshot: ResourceSnapshot {
        monitor.snapshot
    }

    var body: some View {
        StatusBarPanel(title: "Memory and CPU", systemImage: "memorychip") {
            Button("Activity Monitor") {
                openActivityMonitor()
            }
            .buttonStyle(.ds(.ghost))
            .help("Open Activity Monitor")
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
            StatusBarPanelFootnote("Memory is each process's footprint, as Activity Monitor shows it. CPU is a share of one core. Updated every 2 seconds.")
        }
    }

    /// the reference app's summary line: total CPU and memory, with the total's trend.
    private var summary: some View {
        HStack(spacing: DS.Space.md) {
            Text(ResourceFormat.cpu(snapshot.cpu))
                .foregroundStyle(.dsTextPrimary)
            StatusBarDivider()
            Text(ResourceFormat.memory(snapshot.memory))
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

    private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
