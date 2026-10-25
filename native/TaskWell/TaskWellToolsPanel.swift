import ACP
import NativeCommands
import SwiftUI

struct TaskWellToolsPanel<Destination: View>: View {
    let content: TaskWellContent
    let identity: TaskWellIdentity
    @Bindable var tools: SessionToolsScreenModel
    let detail: (TaskWellTool) -> TaskWellToolDetail
    @ViewBuilder var destination: (TaskWellTool) -> Destination
    @State private var hovered: TaskWellTool?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            SeparatorLine()
            worker
            SeparatorLine()
            if let page = tools.wellPage {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Button("Back to tools", systemImage: "chevron.left", action: tools.showWellTools)
                        .buttonStyle(.ds(.ghost))
                    CappedHeightScrollView(maxHeight: DS.TaskWell.devMaxHeight) {
                        VStack(alignment: .leading, spacing: DS.Space.sm) { destination(page) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(DS.Space.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(TaskWellTool.allCases.filter(tools.wellToolAvailable)) { tool in
                        row(tool, detail: detail(tool))
                    }
                }
                .padding(DS.Space.sm)
            }
            SeparatorLine()
            footer
        }
        .frame(width: DS.TaskWell.panelWidth)
        .dsPopoverBackground()
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            if tools.wellPage != nil { tools.showWellTools() } else { tools.showsWell = false }
            return .handled
        }
    }

    private var worker: some View {
        HStack(spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(
                    "\(Text(content.agent).foregroundStyle(.dsTextPrimary))\(Text(identity.model.map { " · \($0)" } ?? "").foregroundStyle(.dsTextTertiary).font(.dsCallout))"
                )
                .font(.dsCalloutMedium)
                .lineLimit(1).truncationMode(.middle)
                Text([identity.machine, identity.timing].compactMap { $0 }.joined(separator: " · "))
                    .font(DS.TaskWell.body).foregroundStyle(.dsTextTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if identity.isManaged {
                Image(systemName: "lock").accessibilityLabel("Managed worker settings")
            } else if let fraction = identity.contextFraction {
                HStack(spacing: DS.Space.sm) {
                    ContextUsageRing(fraction: fraction, size: DS.TaskWell.contextRing)
                        .accessibilityHidden(true)
                    Text("\(DSFormat.percent(min(max(fraction, 0), 1))) context")
                }
                .fixedSize()
            }
        }
        .font(DS.TaskWell.caption)
        .foregroundStyle(.dsTextTertiary)
        .padding(.vertical, DS.Space.lg)
        .padding(.horizontal, DS.Space.xl)
    }

    /// One line: the branch's middle gives way before the administrator's name does.
    private var footer: some View {
        HStack(spacing: DS.Space.sm) {
            checkout
            Spacer(minLength: DS.Space.md)
            management
                .layoutPriority(1)
        }
        .font(DS.TaskWell.caption)
        .foregroundStyle(.dsTextTertiary)
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
        .frame(minHeight: DS.TaskWell.footerHeight)
    }

    /// The project, then its branch, as the title names them.
    private var checkout: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(.dsTextQuaternary)
            Text(identity.project)
            if let branch = identity.branch {
                Text("/").foregroundStyle(.dsTextQuaternary)
                Text(branch).truncationMode(.middle)
            }
        }
        .lineLimit(1)
        .help([identity.project, identity.branch].compactMap { $0 }.joined(separator: " / "))
    }

    @ViewBuilder private var management: some View {
        if let management = identity.management {
            Label(management, systemImage: "lock")
                .lineLimit(1)
        }
    }

    private func row(_ tool: TaskWellTool, detail: TaskWellToolDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                tools.performWellTool(tool)
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: tool.symbol)
                        .foregroundStyle(.dsTextSecondary)
                        .frame(width: DS.TaskWell.rowIconWidth, alignment: .leading)
                    Text(tool.title)
                        .foregroundStyle(detail.unavailableReason == nil ? .dsTextPrimary : .dsTextTertiary)
                        .frame(width: DS.TaskWell.rowTitleWidth, alignment: .leading)
                    HStack(spacing: DS.Space.sm) {
                        if detail.isRunning { StatusDot(color: .dsSuccess) }
                        Text(detail.text).lineLimit(1).truncationMode(.middle)
                        if let since = detail.runningSince {
                            ElapsedTimeText(since: since).fixedSize().foregroundStyle(.dsTextTertiary)
                        }
                        if let stats = detail.stats { DiffStatsText(stats: stats).fixedSize() }
                    }
                    .font(DS.TaskWell.rowDetail)
                    .foregroundStyle(detail.unavailableReason == nil ? .dsTextSecondary : .dsTextTertiary)
                    Spacer(minLength: DS.Space.sm)
                    if detail.isManaged {
                        Image(systemName: "lock").foregroundStyle(.dsTextTertiary)
                    } else {
                        Text(CommandRegistry.shared.shortcut(for: tool.command)?.displayString ?? "")
                            .font(DS.TaskWell.shortcut)
                            .foregroundStyle(.dsTextQuaternary)
                            .fixedSize()
                    }
                }
                .font(DS.TaskWell.row)
                .padding(.leading, DS.Space.md)
                .padding(.trailing, DS.TaskWell.rowTrailing)
                .frame(minHeight: DS.TaskWell.rowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(detail.unavailableReason != nil)
            .background(
                detail.isSelected ? .dsSelected : hovered == tool ? .dsHover : .clear,
                in: .rect(cornerRadius: DS.Radius.card)
            )
            .trackHover(Binding(get: { hovered == tool }, set: { hovered = $0 ? tool : nil }))
            .dsHitTarget(DS.TaskWell.rowHeight)
            .accessibilityIdentifier("taskWell.\(tool.title)")
            if let reason = detail.unavailableReason ?? detail.note {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    Text(reason)
                        .font(DS.TaskWell.body).foregroundStyle(.dsTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let recovery = detail.recovery {
                        Button(recovery.title, action: recovery.action)
                            .buttonStyle(.ds(.secondary, size: .small))
                            .accessibilityIdentifier("taskWell.\(tool.title).recovery")
                    }
                }
                .padding(.leading, DS.Space.md + DS.TaskWell.rowIconWidth)
                .padding(.trailing, DS.Space.md)
                .padding(.bottom, DS.Space.md)
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: DS.TaskWell.gap) {
            TaskSignal(
                status: content.status, isUnread: content.status == .done, placement: .well,
                attentionSince: content.attentionSince
            )
            .frame(width: DS.TaskWell.signal, height: DS.TaskWell.signal)
            if let outcome = content.outcome {
                Text(content.changedFiles(of: outcome))
                DiffStatsText(stats: DiffStats(added: outcome.linesAdded, removed: outcome.linesRemoved))
                    .font(DS.TaskWell.object)
            } else {
                Text(content.verb.isEmpty ? content.agent : content.verb)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize()
                if let object = content.object {
                    Text(object).font(DS.TaskWell.object).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: DS.Space.sm)
            Kbd("esc", compact: true)
        }
        .font(DS.TaskWell.body)
        .padding(.leading, DS.TaskWell.panelHeaderLeading)
        .padding(.trailing, DS.TaskWell.panelHeaderTrailing)
        .frame(height: DS.TaskWell.panelHeaderHeight)
    }
}

#if DEBUG
#Preview("Well - Tools, managed, remote and long content") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            TaskWellPanelPreview()
            TaskWellPanelPreview(isManaged: true)
            TaskWellPanelPreview(isRemote: true)
        }
    }
}
#endif
