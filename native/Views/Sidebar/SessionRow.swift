import ACP
import AppKit
import SwiftUI

/// A session in the sidebar (the reference app's workspace row): the agent's glyph, the session's status, its
/// title and age, and `accessory` (the context-usage ring, or whatever the Usage feature supplies)
/// at the trailing edge. Double-click, Return or the context menu renames it in place.
struct SessionRow<Accessory: View>: View {
    @Environment(AppModel.self) private var model
    let summary: SessionSummary
    let accessory: Accessory
    let select: () -> Void

    private var session: SessionModel? {
        model.session(summary.id)
    }

    var body: some View {
        if model.renaming == summary.id {
            SessionTitleField(summary: summary, status: TaskStatus(session))
        } else {
            TaskRow(
                title: model.title(for: summary),
                status: TaskStatus(session),
                isSelected: model.selection == summary.id,
                date: session?.lastActivity ?? summary.info.updatedDate,
                badge: badge,
                leadingSymbol: summary.agent.symbolName,
                accessory: accessory,
                action: select
            )
            .help("\(summary.agent.displayName) · \(model.title(for: summary))")
            // Double-clicking renames, like a file in the Finder.
            .simultaneousGesture(TapGesture(count: 2).onEnded(rename))
            .contextMenu { menu }
            .accessibilityHint("\(summary.agent.displayName) session. Return renames it.")
            .accessibilityActions {
                Button("Rename", action: rename)
                Button("Move Up") { model.move(target, .up) }
                Button("Move Down") { model.move(target, .down) }
            }
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Rename…", action: rename)
        Divider()
        Button("Move Up") { model.move(target, .up) }
            .disabled(!model.canMove(target, .up))
        Button("Move Down") { model.move(target, .down) }
            .disabled(!model.canMove(target, .down))
        Divider()
        Button("Copy Session ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary.info.sessionId.rawValue, forType: .string)
        }
    }

    private var target: SidebarMoveTarget {
        .session(summary.id, in: summary.project)
    }

    /// Queued follow-ups, counted at the trailing edge.
    private var badge: TaskBadge? {
        guard let count = session?.queuedPrompts.count, count > 0 else { return nil }
        return .count(count)
    }

    private func rename() {
        model.renaming = summary.id
    }
}

extension TaskStatus {
    /// How the sidebar shows a session. One that hasn't been opened in this run is idle.
    init(_ session: SessionModel?) {
        guard let session else {
            self = .idle
            return
        }
        if session.needsApproval {
            self = .needsPermission
            return
        }
        self =
            switch session.phase {
            case .loading: .starting
            case .prompting: .working
            case .disconnected: .failed
            case .idle: .idle
            }
    }
}

/// The trailing indicator task rows show until the Usage feature supplies its own: the reference app's
/// context ring, once a session has used most of its context window.
struct SessionContextUsage: View {
    @Environment(AppModel.self) private var model
    let summary: SessionSummary

    /// the reference app shows the ring past 70%.
    private static let threshold = 0.7

    var body: some View {
        if let fraction = model.session(summary.id)?.state.usage?.fractionUsed, fraction >= Self.threshold {
            ContextUsageRing(fraction: fraction)
        }
    }
}
