import ACP
import SwiftUI

struct SessionView: View {
    let session: SessionModel
    /// The subagent whose conversation is open in the inspector.
    @State private var openSubagent: SessionID?

    var body: some View {
        TranscriptView(session: session) { openSubagent = $0 }
            // A bar rather than an inset, so the transcript gets the system scroll edge effect under it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                ComposerView(session: session)
            }
            .focusedSceneValue(\.activeSession, session)
            .navigationTitle(session.displayTitle)
            .navigationSubtitle(session.cwd.abbreviatedPath)
            .inspector(isPresented: Binding(get: { openSubagent != nil }, set: { if !$0 { openSubagent = nil } })) {
                if let id = openSubagent, let subagent = session.state.subagents.first(where: { $0.id == id }) {
                    SubagentInspector(subagent: subagent, child: session.child(id))
                        .inspectorColumnWidth(min: 340, ideal: 420, max: 640)
                }
            }
    }
}

/// The readable column width shared by the transcript and the composer.
let transcriptColumnWidth: CGFloat = 760

/// A session's conversation. Also shows a subagent's conversation in the inspector.
struct TranscriptView: View {
    let session: SessionModel
    let openSubagent: (SessionID) -> Void

    var body: some View {
        let rows = TranscriptRow.rows(from: session.state.items)
        let spacings = zip([nil] + rows.dropLast(), rows).map { previous, row in previous.map { spacing(between: $0, and: row) } ?? 0 }
        // Only the oldest pending request answers the permission shortcuts, so they're never ambiguous.
        let shortcutTarget = session.state.pendingPermissions.first?.toolCallID
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(zip(rows, spacings)), id: \.0.id) { row, spacing in
                    self.row(row, shortcutTarget: shortcutTarget)
                        .padding(.top, spacing)
                }
                if session.phase == .prompting {
                    WorkingIndicator()
                        .padding(.top, 16)
                }
            }
            .frame(maxWidth: transcriptColumnWidth)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .overlay {
            if session.phase == .loading {
                ProgressView("Loading session…")
            } else if session.state.items.isEmpty {
                ContentUnavailableView("What should we work on?", systemImage: "sparkles", description: Text(session.cwd.abbreviatedPath))
            }
        }
    }
}

extension TranscriptView {
    @ViewBuilder
    private func row(_ row: TranscriptRow, shortcutTarget: String?) -> some View {
        switch row {
        case .exploration(let calls):
            // Calls waiting for approval are never folded, so a group has nothing to answer.
            ToolActivityGroupView(calls: calls) { _ in }
        case .item(.message(let message)):
            MessageView(message: message)
        case .item(.toolCall(let call)):
            ToolCallView(call: call) { option in
                Task { await session.choose(option, forToolCall: call.id) }
            }
            .environment(\.permissionShortcutsEnabled, call.id == shortcutTarget)
        case .item(.notice(let notice)):
            NoticeView(notice: notice)
        case .item(.subagent(let subagent)):
            SubagentCard(subagent: subagent) { openSubagent(subagent.id) }
        case .item(.sessionMessage(let message)):
            SessionMessageView(message: message, sessionID: session.id, name: name(for:))
        }
    }

    /// Tool activity reads as one dense block, Factory style; everything else gets room to breathe.
    private func spacing(between previous: TranscriptRow, and next: TranscriptRow) -> CGFloat {
        previous.isToolActivity && next.isToolActivity ? 2 : 16
    }

    /// How to refer to another session in this transcript's session messages.
    private func name(for id: SessionID?) -> String {
        if let subagent = session.state.subagents.first(where: { $0.id == id }) {
            return subagent.title ?? "subagent"
        }
        if let id, id == session.parentID {
            return "the parent session"
        }
        // A sibling task, or a session this one can't name yet.
        return "another task"
    }
}

private extension TranscriptRow {
    var isToolActivity: Bool {
        switch self {
        case .exploration, .item(.toolCall): true
        default: false
        }
    }
}

private struct WorkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Working…")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
