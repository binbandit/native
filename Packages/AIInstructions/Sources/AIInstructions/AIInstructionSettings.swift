import Foundation

/// Every instruction the user (or their organization) wrote, and which one applies where: the
/// organization's, then the project's own, then the user's global ones.
public struct AIInstructionSettings: Hashable, Sendable {
    /// What applies to a purpose in a project, for showing where it comes from.
    public enum Source: Hashable, Sendable {
        case organization
        case project
        case global
    }

    /// The user's instructions for each purpose, everywhere.
    public var global: [AIInstructionPurpose: String]
    /// Projects (by `AIInstructionProject.key(for:)`) whose own instructions replace the global
    /// ones for a purpose. An empty text replaces them with none.
    public var projects: [String: [AIInstructionPurpose: String]]
    /// The organization's instructions. While set they're all that apply, and nothing else counts.
    public var managed: [AIInstructionPurpose: String]?

    public init(
        global: [AIInstructionPurpose: String] = [:], projects: [String: [AIInstructionPurpose: String]] = [:],
        managed: [AIInstructionPurpose: String]? = nil
    ) {
        self.global = global
        self.projects = projects
        self.managed = managed
    }

    /// Where the instructions for `purpose` in the project `projectKey` come from.
    public func source(for purpose: AIInstructionPurpose, inProject projectKey: String?) -> Source {
        if managed != nil { return .organization }
        if let projectKey, projects[projectKey]?[purpose] != nil { return .project }
        return .global
    }

    /// The text that applies to `purpose` in the project `projectKey` (nil outside any project).
    public func text(for purpose: AIInstructionPurpose, inProject projectKey: String?) -> String {
        switch source(for: purpose, inProject: projectKey) {
        case .organization: managed?[purpose] ?? ""
        case .project: projectKey.flatMap { projects[$0]?[purpose] } ?? ""
        case .global: global[purpose] ?? ""
        }
    }

    /// What's added to `purpose`'s prompt for work in `folder`, which may be a project, a folder in
    /// one, or a task's worktree of one. Nil folder or none of the projects: the global instructions.
    public func addition(for purpose: AIInstructionPurpose, in folder: URL?) -> AIInstructionAddition? {
        let projectKey = folder.flatMap { AIInstructionProject.key(containing: $0, among: projects.keys) }
        return AIInstructionAddition(text(for: purpose, inProject: projectKey))
    }

    // MARK: - Property lists

    /// Purposes by raw value, as they're stored in preferences and set in a policy. Unknown
    /// purposes (from a newer version, or a typo) are left out.
    public static func purposes(_ dictionary: [String: String]) -> [AIInstructionPurpose: String] {
        Dictionary(
            dictionary.compactMap { key, value in AIInstructionPurpose(rawValue: key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first })
    }

    public static func propertyList(_ purposes: [AIInstructionPurpose: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: purposes.map { ($0.key.rawValue, $0.value) })
    }
}
