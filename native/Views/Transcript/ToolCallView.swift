import ACP
import AppKit
import SwiftUI

/// One tool call, modeled on the reference app's tool rows: a dense one-line row (icon, verb, subject) without
/// a card, a shimmer while the tool runs, a trailing word only when something needs attention, and
/// a chevron that appears on hover. Details open into a framed panel below the row; while the agent
/// waits for approval they stay open above the permission buttons.
struct ToolCallView: View {
    let call: ToolCallState
    let onChoose: (PermissionOption) -> Void

    @State private var isExpanded = false

    var body: some View {
        let presentation = ToolPresentation(call)
        let phase = ToolPhase(call)
        let hasDetails = detailsAvailable(for: presentation)
        let showsDetails = hasDetails && (isExpanded || phase == .awaitingApproval)
        VStack(alignment: .leading, spacing: 2) {
            ToolRow(
                presentation: presentation,
                phase: phase,
                isExpandable: hasDetails && phase != .awaitingApproval,
                isExpanded: showsDetails,
                toggle: {
                    withAnimation(.reveal) { isExpanded.toggle() }
                },
                accessory: {
                    if showsDetails, case .command(let command) = presentation.body {
                        CopyButton(text: ToolOutput.copyText(command: command, call: call))
                    }
                }
            )
            if showsDetails {
                ToolDetailFrame(isEmphasized: phase == .awaitingApproval) {
                    ToolCallBody(call: call, presentation: presentation, phase: phase)
                }
                .transition(RevealTransition())
            }
            if let permission = call.permission {
                PermissionButtons(options: permission.options, onChoose: onChoose)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: phase)
    }

    private func detailsAvailable(for presentation: ToolPresentation) -> Bool {
        switch presentation.body {
        case .command, .mcp: return true
        case .generic, .diff, .lines: break
        }
        guard call.content.isEmpty else { return true }
        guard let rawInput = call.rawInput else { return false }
        return rawInput != .null && !rawInput.isEmptyObject
    }
}

/// Where a call is in its lifecycle, as the row shows it.
enum ToolPhase: Equatable {
    case running, awaitingApproval, completed, failed, cancelled

    init(_ call: ToolCallState) {
        if call.permission != nil {
            self = .awaitingApproval
            return
        }
        // Claude Code leaves calls `pending` while they run, so both open states read as running.
        self = switch call.status {
        case .pending, .inProgress: .running
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }
}

private struct ToolRow<Accessory: View>: View {
    let presentation: ToolPresentation
    let phase: ToolPhase
    let isExpandable: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let accessory: Accessory

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    icon
                    title
                    if isExpandable {
                        DisclosureChevron(isExpanded: isExpanded)
                            .opacity(isHovering ? 1 : 0)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isExpandable)
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilityValue)

            accessory
            stateLabel
        }
        .padding(.vertical, 5)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    private var icon: some View {
        Group {
            if presentation.showsStatusIcon {
                // Subagent rows: their status, not the tool, is what matters at a glance.
                Image(systemName: statusSymbol)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous), isActive: phase == .running)
                    .foregroundStyle(phase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(.secondary)
            }
        }
        .symbolRenderingMode(.hierarchical)
        .font(.callout)
        .frame(width: 16)
    }

    private var statusSymbol: String {
        switch phase {
        case .running, .awaitingApproval: "progress.indicator"
        case .completed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .cancelled: "stop.circle"
        }
    }

    private var title: some View {
        HStack(spacing: 6) {
            if let verb = presentation.verb {
                Text(verb)
                    .foregroundStyle(isHovering && isExpandable ? .primary : .secondary)
                    .shimmering(phase == .running)
                    .layoutPriority(1)
            }
            subject
            if let subtitle = presentation.subtitle {
                Text(subtitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder private var subject: some View {
        // Subagent rows already animate their status icon.
        let text = Text(presentation.subject)
            .truncationMode(.middle)
            .shimmering(phase == .running && !presentation.showsStatusIcon)
        switch presentation.subjectStyle {
        case .plain:
            text.foregroundStyle(subjectStyle)
        case .command:
            text
                .font(.callout.monospaced())
                .foregroundStyle(subjectStyle)
        case .emphasized:
            text.foregroundStyle(.primary)
        case .chip:
            HStack(spacing: 7) {
                text.foregroundStyle(isHovering && isExpandable ? .primary : .secondary)
                if let stats = presentation.stats {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1, height: 11)
                    DiffStatsText(stats: stats)
                }
            }
            .font(.callout)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.fill.tertiary, in: .rect(cornerRadius: 6, style: .continuous))
        }
    }

    /// A subject reads tertiary after a verb and secondary on its own; hover lifts it to primary.
    private var subjectStyle: HierarchicalShapeStyle {
        if isHovering, isExpandable { .primary } else if presentation.verb == nil { .secondary } else { .tertiary }
    }

    @ViewBuilder private var stateLabel: some View {
        switch phase {
        case .awaitingApproval:
            Text("Approval required")
                .font(.subheadline)
                .foregroundStyle(.tint)
        case .failed where !presentation.showsStatusIcon:
            Text(presentation.failureLabel)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case .cancelled:
            Text("Interrupted")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        default:
            EmptyView()
        }
    }

    private var accessibilityValue: String {
        switch phase {
        case .running: "Running"
        case .awaitingApproval: "Waiting for approval"
        case .completed: "Completed"
        case .failed: presentation.failureLabel
        case .cancelled: "Interrupted"
        }
    }
}

/// The framed panel a row's details open into, capped in height and scrolling beyond that.
private struct ToolDetailFrame<Content: View>: View {
    let isEmphasized: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HeightCappedScrollView(maxHeight: 266) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.fill.quinary, in: shape)
        .overlay {
            shape.strokeBorder(isEmphasized ? AnyShapeStyle(.tint.opacity(0.5)) : AnyShapeStyle(.separator))
        }
        .clipShape(shape)
        .containerShape(shape)
    }
}

private struct CopyButton: View {
    let text: String

    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Copy command and output")
        .accessibilityLabel("Copy command and output")
    }
}

/// One button per option, in the agent's order. These sit in content, so they're standard bordered
/// controls rather than Liquid Glass. ⌘Y allows once, ⌥⌘Y always and ⌘⇧⌫ rejects (docs/keyboard.md),
/// unless the transcript turns shortcuts off for this request (only one pending request owns them).
private struct PermissionButtons: View {
    let options: [PermissionOption]
    let onChoose: (PermissionOption) -> Void

    @Environment(\.permissionShortcutsEnabled) private var shortcutsEnabled

    var body: some View {
        // Long option names ("Yes, allow all edits in … during this session") may not fit in a row.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                buttons
                Spacer(minLength: 12)
                shortcutHint
            }
            VStack(alignment: .leading, spacing: 8) {
                buttons
                shortcutHint
            }
        }
    }

    private var buttons: some View {
        ForEach(options) { option in
            let button = Button(option.name, role: option.isRejection ? .destructive : nil) {
                onChoose(option)
            }
            .keyboardShortcut(shortcutsEnabled ? shortcut(for: option) : nil)
            if option.kind == .allowOnce {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var shortcutHint: some View {
        if shortcutsEnabled {
            let hints = options.compactMap { option in Self.symbols(for: option.kind).map { "\($0) \(option.name)" } }
            Text(hints.joined(separator: "  ·  "))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func shortcut(for option: PermissionOption) -> KeyboardShortcut? {
        switch option.kind {
        case .allowOnce: KeyboardShortcut("y", modifiers: .command)
        case .allowAlways: KeyboardShortcut("y", modifiers: [.command, .option])
        case .rejectOnce: KeyboardShortcut(.delete, modifiers: [.command, .shift])
        case .rejectAlways: nil
        }
    }

    private static func symbols(for kind: PermissionOption.Kind) -> String? {
        switch kind {
        case .allowOnce: "⌘Y"
        case .allowAlways: "⌥⌘Y"
        case .rejectOnce: "⌘⇧⌫"
        case .rejectAlways: nil
        }
    }
}

extension EnvironmentValues {
    /// Whether a pending permission request answers to its shortcuts. Turn it off for all but one
    /// request when several are pending, so the shortcuts stay unambiguous.
    @Entry var permissionShortcutsEnabled = true
}

#if DEBUG
#Preview("Tool calls") {
    ScrollView {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(TranscriptFixtures.toolCalls, id: \.id) { call in
                ToolCallView(call: call) { _ in }
            }
        }
        .padding(20)
    }
    .frame(width: 640, height: 760)
}
#endif
