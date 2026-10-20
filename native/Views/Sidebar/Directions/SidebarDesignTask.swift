#if DEBUG
import ACP
import SwiftUI

/// One task as the sidebar directions show it, read from the model once per update: where it stands
/// in the one status vocabulary, and the line each direction can put under its title.
struct SidebarDesignTask: Identifiable {
    let summary: SessionSummary
    let project: Project
    let title: String
    let status: TaskStatus
    let isUnread: Bool
    let isArchived: Bool
    let date: Date?
    /// What it waits on the user for: "Allow `swift test`?".
    let ask: String?
    /// What it's doing right now: the open tool call's title.
    let doing: String?
    /// Why the last turn failed, as the transcript says it.
    let failure: String?
    let editedFiles: Int
    /// The machine it runs on when that isn't this Mac (fixture only until remote hosts land).
    let device: String?

    var id: SessionKey { summary.id }

    /// Its move is the user's: an approval, a question, a plan, or a failure to look at.
    var isYourMove: Bool { status.needsAttention || status == .failed }

    /// The second line a direction shows under the title, when there's something to say.
    var detail: String? {
        if let ask { return ask }
        if status == .failed { return failure ?? "The last turn failed" }
        if status.isActive { return doing ?? "Thinking" }
        return nil
    }

    /// The one word for what the user does next, while it's their move: "Approve", "Answer".
    var nextStep: String? {
        switch status {
        case .needsPermission: "Approve"
        case .needsInput: "Answer"
        case .needsPlanReview: "Review"
        case .failed: "Failed"
        default: nil
        }
    }

    /// The task's latest event, for the timeline: what happened, in a few words.
    var event: String {
        switch status {
        case .needsPermission, .needsInput, .needsPlanReview: ask ?? status.label
        case .failed: failure ?? "Failed"
        case .starting, .working, .waiting: doing ?? "Working"
        case .done:
            editedFiles > 0 ? "Finished, \(editedFiles) \(editedFiles == 1 ? "file" : "files") changed" : "Finished"
        case .cancelled: "Stopped"
        // Nothing known since it was last open: whose task it is.
        case .idle: isArchived ? "Archived" : summary.agent.displayName
        case .paused, .limited: status.label
        }
    }
}

extension AppModel {
    /// Every task in the sidebar, across projects, in each project's order.
    func sidebarDesignTasks(in project: Project.ID? = nil) -> [SidebarDesignTask] {
        projects.all.filter { project == nil || $0.id == project }.flatMap { project in
            sessions(in: project.id).map { sidebarDesignTask($0, in: project) }
        }
    }

    /// The archived tasks, newest first.
    func sidebarDesignArchived(in project: Project.ID? = nil) -> [SidebarDesignTask] {
        projects.all.filter { project == nil || $0.id == project }
            .flatMap { project in archivedSessions(in: project.id).map { sidebarDesignTask($0, in: project) } }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func sidebarDesignTask(_ summary: SessionSummary, in project: Project) -> SidebarDesignTask {
        let session = session(summary.id)
        let items = session?.state.items ?? []
        var doing: String?
        var failure: String?
        var edited = Set<String>()
        for item in items.reversed() {
            switch item {
            case .toolCall(let call):
                if doing == nil, call.status == .inProgress || call.status == .pending {
                    doing = call.title
                }
                for case .diff(let diff) in call.content {
                    edited.insert(diff.path)
                }
            case .notice(let notice) where notice.isError:
                failure = failure ?? notice.text
            default:
                break
            }
        }
        return SidebarDesignTask(
            summary: summary,
            project: project,
            title: title(for: summary),
            status: session?.taskStatus ?? .idle,
            isUnread: isUnread(summary.id),
            isArchived: isArchived(summary.id),
            date: session?.lastActivity ?? summary.info.updatedDate,
            ask: session?.sidebarAsk,
            doing: doing,
            failure: failure,
            editedFiles: edited.count,
            device: SidebarDesignFixture.devices[summary.id]
        )
    }

    /// A row was clicked: open it and focus its composer, as today's sidebar does.
    func selectFromSidebarDesign(_ key: SessionKey) {
        selection = key
        Task {
            await loadSession(key)
            session(key)?.wantsComposerFocus = true
        }
    }
}

/// What the sidebar directions link to beyond tasks, from `RootView`: the pages that take the detail
/// column.
struct SidebarDesignDestinations {
    var isShowingPullRequests: Bool
    var showPullRequests: () -> Void
    /// Nil while Workflows is off and has nothing to show.
    var workflows: (isShown: Bool, show: () -> Void)?
}
#endif
