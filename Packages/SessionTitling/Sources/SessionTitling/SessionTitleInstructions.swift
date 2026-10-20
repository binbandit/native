import AIInstructions
import Foundation

/// The user's own instructions for titles (Settings ▸ AI Instructions), everywhere they apply, so
/// whoever writes a title (the host, with no app attached) applies the ones for the task's folder:
/// the organization's while it manages them, else the project's own, else the global ones.
public struct SessionTitleInstructions: Hashable, Sendable {
    public var global: String?
    /// Projects' own, by `AIInstructionProject.key(for:)`; an empty text means none.
    public var projects: [String: String]
    /// The organization's while it manages instructions; an empty text means it gives none.
    public var managed: String?

    public init(global: String? = nil, projects: [String: String] = [:], managed: String? = nil) {
        self.global = global
        self.projects = projects
        self.managed = managed
    }

    /// The instructions for titles in `settings`.
    public init(_ settings: AIInstructionSettings) {
        self.init(
            global: settings.global[.title], projects: settings.projects.compactMapValues { $0[.title] },
            managed: settings.managed.map { $0[.title] ?? "" })
    }

    /// What's added to the title prompt for a task in `folder`.
    public func addition(in folder: URL) -> AIInstructionAddition? {
        AIInstructionSettings(
            global: global.map { [.title: $0] } ?? [:], projects: projects.mapValues { [.title: $0] },
            managed: managed.map { [.title: $0] }
        ).addition(for: .title, in: folder)
    }
}
