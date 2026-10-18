import Foundation

/// Something wrong with a skill, in words for the user. Errors mean agents skip it (or some do);
/// warnings mean it loads but isn't portable.
public enum SkillProblem: Hashable, Sendable {
    /// A folder in a skills directory with no SKILL.md, which every agent ignores.
    case missingSkillFile
    case unreadable
    case noFrontmatter
    case malformedFrontmatter(line: Int, reason: String)
    case missingName
    case missingDescription
    case invalidName(String)
    case nameDiffersFromFolder(name: String, folder: String)
    case descriptionTooLong(Int)
    /// One agent finds different skills with the same name in several places.
    case duplicate(agent: SkillAgentFormat, paths: [String])

    public enum Severity: Hashable, Sendable {
        case error
        case warning
    }

    public var severity: Severity {
        switch self {
        case .missingSkillFile, .unreadable, .noFrontmatter, .malformedFrontmatter, .missingName, .missingDescription:
            .error
        case .invalidName, .nameDiffersFromFolder, .descriptionTooLong, .duplicate: .warning
        }
    }

    public var message: String {
        switch self {
        case .missingSkillFile: "There's no SKILL.md in this folder, so agents ignore it."
        case .unreadable: "Native couldn't read its SKILL.md."
        case .noFrontmatter: "SKILL.md doesn't start with a `---` frontmatter block, so agents can't tell what it is."
        case .malformedFrontmatter(let line, let reason):
            "SKILL.md's frontmatter is malformed at line \(line): \(reason)"
        case .missingName: "SKILL.md's frontmatter has no name."
        case .missingDescription: "SKILL.md's frontmatter has no description, so agents won't know when to use it."
        case .invalidName(let name):
            "\"\(name)\" isn't a valid skill name (lowercase letters, digits and hyphens, at most 64), so some agents skip it."
        case .nameDiffersFromFolder(let name, let folder):
            "It's named \"\(name)\" but its folder is \"\(folder)\"; some agents expect them to match."
        case .descriptionTooLong(let count):
            "Its description is \(count) characters; the limit is \(SkillDocument.maximumDescriptionLength)."
        case .duplicate(let agent, let paths):
            "\(agent.displayName) finds \(paths.count) different skills with this name and loads only one."
        }
    }
}
