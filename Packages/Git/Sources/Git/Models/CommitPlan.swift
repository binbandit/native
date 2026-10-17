import Foundation

/// The working changes split into commits, made in order. Each file is in at most one group;
/// files in no group stay uncommitted.
public struct CommitPlan: Hashable, Sendable {
    public struct Group: Hashable, Sendable, Identifiable {
        public let id: UUID
        /// Subject, then optionally a blank line and a body.
        public var message: String
        public var paths: [String]

        public init(id: UUID = UUID(), message: String, paths: [String]) {
            self.id = id
            self.message = message
            self.paths = paths
        }
    }

    public var groups: [Group]

    public init(groups: [Group]) {
        self.groups = groups
    }

    /// Every path the plan commits.
    public var paths: [String] { groups.flatMap(\.paths) }

    /// A proposed grouping (from a model) made to fit the files actually changed: unknown paths and
    /// repeats are dropped (the first group keeps a file), empty groups go, and any changed file the
    /// proposal missed lands in a last group so nothing is silently left out.
    public static func reconciling(
        _ proposal: [(message: String, paths: [String])], changedPaths: [String], leftoverMessage: String
    ) -> CommitPlan {
        let changed = Set(changedPaths)
        var placed: Set<String> = []
        var groups: [Group] = []
        for (message, paths) in proposal {
            let kept = paths.filter { changed.contains($0) && placed.insert($0).inserted }
            let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !kept.isEmpty, !message.isEmpty { groups.append(Group(message: message, paths: kept)) }
        }
        let leftover = changedPaths.filter { !placed.contains($0) }
        if !leftover.isEmpty { groups.append(Group(message: leftoverMessage, paths: leftover)) }
        return CommitPlan(groups: groups)
    }

    /// One group per top-level folder (files at the root together), for when no model can draft a
    /// grouping. Messages name the folder; callers usually draft better ones per group.
    public static func byFolder(_ paths: [String]) -> CommitPlan {
        var order: [String] = []
        var byFolder: [String: [String]] = [:]
        for path in paths {
            let folder = path.contains("/") ? String(path.prefix { $0 != "/" }) : ""
            if byFolder[folder] == nil { order.append(folder) }
            byFolder[folder, default: []].append(path)
        }
        return CommitPlan(
            groups: order.map { folder in
                Group(message: folder.isEmpty ? "Update project files" : "Update \(folder)", paths: byFolder[folder] ?? [])
            })
    }
}
