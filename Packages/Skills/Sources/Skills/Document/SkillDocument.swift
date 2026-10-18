import Foundation

/// A SKILL.md's frontmatter (the Agent Skills format at agentskills.io, plus the fields agents
/// add), with defaults applied.
public struct SkillFrontmatter: Hashable, Sendable {
    public var name: String?
    public var description: String?
    public var license: String?
    public var compatibility: String?
    /// `version`, or `metadata.version` where the spec keeps it.
    public var version: String?
    /// Tools the skill expects to use without asking (`allowed-tools`); experimental in the spec.
    public var allowedTools: [String] = []
    /// Whether people can run it as a command (`user-invocable`, default true).
    public var isUserInvocable = true
    /// Whether the model may pick it on its own (`disable-model-invocation`, default false).
    public var isModelInvocable = true
    public var metadata: [String: String] = [:]
    /// Keys Native doesn't interpret, kept so the details can show them.
    public var otherKeys: [String] = []

    public init() {}
}

/// A parsed SKILL.md: what it says, its instructions, and anything wrong with it.
public struct SkillDocument: Hashable, Sendable {
    public var frontmatter: SkillFrontmatter
    /// The instructions after the frontmatter.
    public var body: String
    public var problems: [SkillProblem]

    /// The most a description may be in the Agent Skills spec.
    public static let maximumDescriptionLength = 1024

    /// Parses `text`, checking it against the Agent Skills spec. `folderName` is the skill's
    /// folder, which the spec says the name should match.
    public static func parse(_ text: String, folderName: String? = nil) -> SkillDocument {
        guard let (yaml, body) = FrontmatterParser.split(text) else {
            return SkillDocument(frontmatter: SkillFrontmatter(), body: text, problems: [.noFrontmatter])
        }
        let entries: [(key: String, value: FrontmatterValue)]
        do {
            entries = try FrontmatterParser.parse(yaml)
        } catch {
            return SkillDocument(
                frontmatter: SkillFrontmatter(), body: body,
                problems: [.malformedFrontmatter(line: error.line, reason: error.reason)])
        }
        var frontmatter = SkillFrontmatter()
        for (key, value) in entries {
            switch key {
            case "name": frontmatter.name = value.string.flatMap(nonEmpty)
            case "description": frontmatter.description = value.string.flatMap(nonEmpty)
            case "license": frontmatter.license = value.string.flatMap(nonEmpty)
            case "compatibility": frontmatter.compatibility = value.string.flatMap(nonEmpty)
            case "version": frontmatter.version = value.string.flatMap(nonEmpty)
            case "allowed-tools", "tools":
                switch value {
                case .list(let tools): frontmatter.allowedTools = tools
                case .scalar(let tools):
                    frontmatter.allowedTools = tools.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
                case .map: break
                }
            case "user-invocable": frontmatter.isUserInvocable = bool(value) ?? true
            case "disable-model-invocation": frontmatter.isModelInvocable = !(bool(value) ?? false)
            case "metadata":
                if case .map(let map) = value { frontmatter.metadata = map }
            default: frontmatter.otherKeys.append(key)
            }
        }
        if frontmatter.version == nil { frontmatter.version = frontmatter.metadata["version"] }
        return SkillDocument(frontmatter: frontmatter, body: body, problems: check(frontmatter, folderName: folderName))
    }

    private static func check(_ frontmatter: SkillFrontmatter, folderName: String?) -> [SkillProblem] {
        var problems: [SkillProblem] = []
        if let name = frontmatter.name {
            if !isValidName(name) { problems.append(.invalidName(name)) }
            if let folderName, folderName != name {
                problems.append(.nameDiffersFromFolder(name: name, folder: folderName))
            }
        } else {
            problems.append(.missingName)
        }
        if let description = frontmatter.description {
            if description.count > maximumDescriptionLength { problems.append(.descriptionTooLong(description.count)) }
        } else {
            problems.append(.missingDescription)
        }
        return problems
    }

    /// The spec's rule: 1 to 64 lowercase letters, digits and single hyphens, not at either end.
    public static func isValidName(_ name: String) -> Bool {
        guard (1...64).contains(name.count), !name.hasPrefix("-"), !name.hasSuffix("-"), !name.contains("--")
        else { return false }
        return name.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: FrontmatterValue) -> Bool? {
        switch value.string?.lowercased() {
        case "true", "yes", "on": true
        case "false", "no", "off": false
        default: nil
        }
    }
}
