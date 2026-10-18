import ACP
import Foundation

/// A tool call in one line, by its kind and the agent's own title ("Running pnpm test",
/// "Edited Composer.swift"). The Mac's `ToolPresentation` words these per tool; it joins this
/// target once it no longer needs `ToolPhase` from `ToolCallView.swift` (see docs/companion.md).
struct CompanionToolSummary {
    let symbol: String
    /// The one-line row text, in the tense of where the call is.
    let line: String
    /// What it asks permission for: "Run command" plus the subject.
    let request: String
    /// The command or path, for the approval card.
    let detail: String?
    let stats: DiffStats?

    init(_ call: ToolCallState) {
        let isOpen = call.status == .pending || call.status == .inProgress
        let command = call.rawInput?["command"]?.stringValue
        let path = call.locations.first.map { URL(filePath: $0.path).lastPathComponent }
        let subject = path ?? call.title
        let verbs: (open: String, done: String, ask: String)?
        switch call.kind {
        case .read: (symbol, verbs) = ("doc.text", ("Reading", "Read", "Read"))
        case .edit: (symbol, verbs) = ("pencil", ("Editing", "Edited", "Edit"))
        case .delete: (symbol, verbs) = ("trash", ("Deleting", "Deleted", "Delete"))
        case .move: (symbol, verbs) = ("arrow.right.doc.on.clipboard", ("Moving", "Moved", "Move"))
        case .search: (symbol, verbs) = ("magnifyingglass", ("Searching", "Searched", "Search"))
        case .execute: (symbol, verbs) = ("terminal", ("Running", "Ran", "Run"))
        case .fetch: (symbol, verbs) = ("globe", ("Fetching", "Fetched", "Fetch"))
        case .think: (symbol, verbs) = ("brain", nil)
        case .switchMode, .other: (symbol, verbs) = ("wrench.and.screwdriver", nil)
        }
        let title = call.kind == .execute ? (command.map { "`\($0)`" } ?? call.title) : subject
        if let verbs, call.kind != .execute || command != nil {
            line = "\(isOpen ? verbs.open : verbs.done) \(call.kind == .execute ? (command ?? call.title) : subject)"
            request = "\(verbs.ask) \(call.kind == .execute ? "this command" : subject)"
        } else {
            line = call.title
            request = call.title
        }
        _ = title
        detail = command ?? call.locations.first?.path
        let diffs = call.content.compactMap { content -> DiffStats? in
            if case .diff(let diff) = content { DiffStats(oldText: diff.oldText, newText: diff.newText) } else { nil }
        }
        stats =
            diffs.isEmpty
            ? nil
            : diffs.reduce(DiffStats()) { DiffStats(added: $0.added + $1.added, removed: $0.removed + $1.removed) }
    }

    /// The headline for the detail sheet.
    var subject: String { line }
}
