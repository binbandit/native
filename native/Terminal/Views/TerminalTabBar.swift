import SwiftUI
import Terminal

/// The panel's header: the task's terminal tabs, a new-tab button, and a button that hides the
/// panel.
struct TerminalTabBar: View {
    let panel: TerminalPanelModel
    /// False when the terminal isn't available, leaving just the hide button.
    let showsTabs: Bool
    var canAddTab = true
    var isWorkbench = false
    var workbenchActions: AnyView?
    @State private var tabsWidth: CGFloat?

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if showsTabs {
                ScrollView(.horizontal) {
                    HStack(spacing: DS.Space.xxs) {
                        ForEach(panel.tabs.tabs) { tab in
                            TerminalTabButton(
                                tab: tab,
                                label: panel.tabs.label(of: tab),
                                isSelected: tab.id == panel.tabs.selectedID,
                                select: { panel.select(tab.id) },
                                close: { panel.requestClose(tab.id) },
                                restart: { panel.restart(tab.id) },
                                stop: { panel.stopJob(in: tab.id) }
                            )
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { tabsWidth = $0 }
                }
                .scrollIndicators(.never)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: isWorkbench ? tabsWidth : nil)
                if isWorkbench, let workbenchActions {
                    Menu {
                        Button("New Terminal Tab", systemImage: "terminal") { panel.newTab() }
                            .disabled(!canAddTab)
                        Divider()
                        workbenchActions
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add to workbench")
                    .accessibilityLabel("Add to workbench")
                    .dsHitTarget(DS.Size.controlXS)
                } else {
                    IconButton("New Terminal Tab", systemImage: "plus") { panel.newTab() }
                        .disabled(!canAddTab)
                }
            } else {
                Text("Terminal")
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.horizontal, DS.Space.sm)
            }
            Spacer(minLength: DS.Space.md)
            if showsTabs, let tab = panel.tabs.selected, let job = tab.job, job.isRunning {
                TerminalJobControls(job: job) { panel.stopJob(in: tab.id) }
            }
            IconButton("Hide Terminal", systemImage: "chevron.down") { panel.hide() }
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: isWorkbench ? DS.TaskWell.workbenchBarHeight : DS.Size.controlMD)
    }
}

/// One terminal tab: its status, name, and a close button on hover (always, when selected, so it
/// can be reached by touch).
private struct TerminalTabButton: View {
    let tab: TerminalTabList.Tab
    let label: String
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    let restart: () -> Void
    let stop: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        HStack(spacing: DS.Space.xs) {
            statusDot
            Text(label)
                .font(.dsBody)
                .foregroundStyle(isSelected ? .dsTextPrimary : .dsTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)
            TerminalTabCloseButton(action: close)
                .opacity(isSelected || isHovered ? 1 : 0)
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.xs)
        .frame(height: DS.Size.controlXS)
        .background(isSelected ? Color.dsSelected : isHovered ? Color.dsHover : .clear, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: select)
        .trackHover($isHovered)
        .contextMenu {
            if let job = tab.job {
                Button("Run Again", action: restart)
                if job.isRunning {
                    Button(job.isStopping ? "End Now" : "Stop", action: stop)
                }
            } else {
                Button("Restart Shell", action: restart)
            }
            Button("Close Tab", action: close)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close Tab", close)
    }

    @ViewBuilder private var statusDot: some View {
        if let job = tab.job {
            TerminalJobStatusDot(job: job)
        } else {
            shellStatusDot
        }
    }

    @ViewBuilder private var shellStatusDot: some View {
        switch tab.status {
        case .running:
            EmptyView()
        case .exited:
            StatusDot(color: .dsTextTertiary)
        case .failedToStart:
            StatusDot(color: .dsDanger)
        }
    }

    private var accessibilityLabel: String {
        if let job = tab.job {
            return TerminalJobStatusDot.accessibilityLabel(label, job: job)
        }
        return switch tab.status {
        case .running: label
        case .exited: "\(label), exited"
        case .failedToStart: "\(label), didn't start"
        }
    }
}

/// The small × inside a tab, sized to the tab rather than a toolbar button.
private struct TerminalTabCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    /// The tab close button: a 16pt square around a small glyph.
    private static let side: CGFloat = 16

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
                .frame(width: Self.side, height: Self.side)
                .background(isHovered ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.control))
                .contentShape(.rect)
                .dsHitTarget(Self.side)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help("Close Tab")
        .accessibilityLabel("Close Tab")
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Terminal tab bar") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            TerminalTabBar(panel: TerminalPreviewFixtures.panel(), showsTabs: true)
                .background(.dsSurfaceSunken)
            // The terminal isn't available: just its name and Hide.
            TerminalTabBar(panel: TerminalPreviewFixtures.panel(), showsTabs: false)
                .background(.dsSurfaceSunken)
        }
        .frame(width: 640)
    }
}
#endif

#if DEBUG
#Preview("Terminal tabs - Background worktree command") {
    let panel = TerminalPanelModel(workingDirectory: URL(filePath: "/work/task"), engine: { nil })
    panel.attach(TerminalLogPreviewFixtures.running)
    return DSPreviewPair {
        TerminalTabBar(panel: panel, showsTabs: true, canAddTab: false)
            .frame(width: 640)
    }
}
#endif
