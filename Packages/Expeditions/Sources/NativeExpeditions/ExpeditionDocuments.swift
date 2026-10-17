import Foundation
import NativeAutomation

/// The expedition's shared artifacts as Markdown files, for the user to open in any editor:
/// `~/.native/expeditions/<id>/` holds the route, every report and verdict, the logbook and the
/// debrief. Outside the repo, like worktrees, so they never land in a commit.
///
/// Native is the only writer: the files are written read-only, and before each write Native checks
/// that what's there is what it wrote last. A file changed behind its back (any agent can `chmod`)
/// is put back and reported, because the route is the contract the user approved and the reports
/// are the record the reviewer and the user rely on.
@MainActor
public final class ExpeditionDocuments {
    public static let standard = ExpeditionDocuments(root: URL.homeDirectory.appending(path: ".native/expeditions", directoryHint: .isDirectory))

    public let root: URL
    /// What Native last wrote to each file, by path.
    private var written: [String: Data] = [:]

    public init(root: URL) {
        self.root = root
    }

    public func folder(for expedition: Expedition.ID) -> URL {
        root.appending(path: expedition.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    /// Brings the files up to date. Returns the paths it had to put back.
    @discardableResult
    public func write(_ expedition: Expedition) -> [String] {
        let folder = folder(for: expedition.id)
        let files = FileManager.default
        var restored: [String] = []
        for (path, text) in Self.render(expedition) {
            let url = folder.appending(path: path)
            let data = Data(text.utf8)
            let onDisk = try? Data(contentsOf: url)
            if let last = written[url.path], let onDisk, onDisk != last {
                restored.append(path)
            }
            guard onDisk != data else {
                written[url.path] = data
                continue
            }
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            do {
                try data.write(to: url, options: .atomic)
                try files.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
                written[url.path] = data
            } catch {
                written[url.path] = nil
            }
        }
        return restored
    }

    /// Every file and its contents, by path inside the expedition's folder.
    public nonisolated static func render(_ expedition: Expedition) -> [String: String] {
        var files = ["logbook.md": logbook(expedition)]
        if let route = expedition.route {
            files["route.md"] = routeDocument(expedition, route)
        }
        for run in expedition.assignments where run.report != nil {
            files["reports/\(run.id).md"] = "# \(run.assignment.title)\n\n\(agentName(expedition, run.assignment.assignee)) · \(run.status.label)\n\n\(run.report ?? "")\n"
        }
        for run in expedition.checkpoints where !run.verdicts.isEmpty {
            let title = expedition.leg(run.leg)?.title ?? run.leg
            let rounds = run.verdicts.enumerated().map { index, verdict in
                "## Round \(index + 1): \(verdict.outcome == .pass ? "pass" : "changes")\(verdict.note.map { " - \($0)" } ?? "")\n\n\(verdict.findings)"
            }
            files["checkpoints/\(run.leg).md"] = "# Checkpoint: \(title)\n\nReviewed by \(expedition.crew.reviewer.name)\n\n" + rounds.joined(separator: "\n\n") + "\n"
        }
        if let debrief = expedition.debrief {
            files["debrief.md"] = "# \(expedition.title)\n\n\(debrief)\n"
        }
        return files
    }

    private nonisolated static func routeDocument(_ expedition: Expedition, _ route: Route) -> String {
        var lines = ["# \(expedition.title)", "", "## Objective", "", expedition.objective, ""]
        if !route.summary.isEmpty {
            lines += ["## Approach", "", route.summary, ""]
        }
        if !route.questions.isEmpty {
            lines += ["## Questions", ""] + route.questions.map { "- \($0.text)" + ($0.answer.map { "\n  - \($0)" } ?? "") } + [""]
        }
        if !route.assumptions.isEmpty {
            lines += ["## Assumptions", ""] + route.assumptions.map { "- \($0)" } + [""]
        }
        for (index, leg) in route.legs.enumerated() {
            lines += ["## Leg \(index + 1): \(leg.title)", "", leg.outcome, ""]
            for assignment in leg.assignments {
                let status = expedition.assignment(assignment.id)?.status.label ?? "Proposed"
                lines += ["### \(assignment.title)", "", "`\(assignment.id)` · \(agentName(expedition, assignment.assignee)) · \(status)", "", assignment.brief, "", "Done when:"]
                lines += assignment.doneWhen.map { "- \($0)" }
                if !assignment.after.isEmpty {
                    lines += ["", "After: " + assignment.after.map { "`\($0)`" }.joined(separator: ", ")]
                }
                lines.append("")
            }
        }
        if expedition.approvedAt == nil {
            lines += ["_Proposed; not approved yet._", ""]
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func logbook(_ expedition: Expedition) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return (["# Logbook: \(expedition.title)", ""] + expedition.log.map { "- \(formatter.string(from: $0.at)) \($0.text)" }).joined(separator: "\n") + "\n"
    }

    private nonisolated static func agentName(_ expedition: Expedition, _ id: String) -> String {
        expedition.crew.agent(id)?.name ?? id
    }
}
