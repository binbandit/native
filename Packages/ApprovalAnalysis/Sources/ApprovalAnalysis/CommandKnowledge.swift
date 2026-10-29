import CoreFoundation
import Foundation

/// Reviewed descriptions of literal command syntax. Loading and matching never execute a command,
/// inspect its operands, or use the network. See docs/command-knowledge.md for the versioned format.
public struct CommandKnowledge: Equatable, Sendable {
    struct Program: Codable, Equatable, Sendable {
        let executables: [String]
        let commands: [Command]
    }

    struct Command: Codable, Equatable, Sendable {
        let words: [String]
        let summary: String
        let consequence: String
        let destructive: Bool
        let options: [Option]
        let operands: Operands
        let optionsBeforeOperands: Bool?
        let shortClusters: Bool?
        let allowsTerminator: Bool?
        let noSuggestionWithOptions: [String]?
        let noSuggestionWithOperandPrefixes: [String]?
        /// Said instead of `consequence` when an option or operand makes a routine command irreversible.
        let destructiveConsequence: String?
        /// Operands starting with one of these make the command irreversible, like `+main` for a push.
        let destructiveOperandPrefixes: [String]?
    }

    struct Option: Codable, Equatable, Sendable {
        enum ValueMode: String, Codable, Sendable { case none, next, attached }
        let names: [String]
        let summary: String
        let destructive: Bool
        /// none, next, or attached. Attached values also accept a separate next word.
        let value: ValueMode
        let replacement: String?
        let alternative: String?
    }

    struct Operands: Codable, Equatable, Sendable {
        let minimum: Int
        let maximum: Int?
        /// Nil leaves operands unannotated: the words are already in front of the person.
        let summary: String?
        let paths: Bool
    }

    struct Location: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case homePrefix, component }
        /// homePrefix or component. These identify conventional names, never measured contents.
        let kind: Kind
        let path: String
        let summary: String
    }

    var programs: [Program] = []
    var locations: [Location] = []
    public private(set) var problems: [String] = []

    public init() {}

    public static let bundled: Self = {
        guard let url = Bundle.module.url(forResource: "commands", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return Self(problems: ["Bundled command knowledge could not be read."]) }
        return load(data)
    }()

    private init(problems: [String]) { self.problems = problems }

    /// A bad entry is rejected independently; valid neighbours still load. Messages identify the
    /// entry and field, without repeating arbitrary input that might contain confidential data.
    public static func load(_ data: Data) -> Self {
        guard data.count <= 1_048_576 else { return Self(problems: ["Command knowledge exceeds 1 MiB; ignored."]) }
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                Set(root.keys) == ["version", "programs", "locations"],
                let version = root["version"] as? NSNumber,
                CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
                let programs = root["programs"] as? [Any], programs.count <= 256,
                let locations = root["locations"] as? [Any], locations.count <= 64
            else {
                return Self(problems: [
                    "Command knowledge needs version 1, programs (up to 256), and locations (up to 64); ignored."
                ])
            }
            var result = Self()
            for (index, raw) in programs.enumerated() {
                do {
                    let program = try CommandKnowledgeValidation.program(raw)
                    guard !program.executables.contains(where: { result.recognizes($0) }) else {
                        throw CommandKnowledgeValidation.Invalid("executables overlap another entry")
                    }
                    result.programs.append(program)
                } catch {
                    result.problems.append(
                        "Program \(index + 1): \(CommandKnowledgeValidation.message(error)); ignored.")
                }
            }
            for (index, raw) in locations.enumerated() {
                do { result.locations.append(try CommandKnowledgeValidation.location(raw)) } catch {
                    result.problems.append(
                        "Location \(index + 1): \(CommandKnowledgeValidation.message(error)); ignored.")
                }
            }
            return result
        } catch { return Self(problems: ["Command knowledge is not valid JSON; ignored."]) }
    }

    /// Add internal tools, never redefine a shipped tool or a tool from an earlier source.
    public func adding(_ other: Self, source: String) -> Self {
        var result = self
        result.problems += other.problems.map { "\(source): \($0)" }
        for (index, program) in other.programs.enumerated() {
            guard !program.executables.contains(where: { result.recognizes($0) }) else {
                result.problems.append("\(source): program \(index + 1) overlaps existing executables; ignored.")
                continue
            }
            result.programs.append(program)
        }
        // Locations never change risk, and the earlier source wins for identical matches.
        result.locations += other.locations.filter { location in
            !result.locations.contains { $0.kind == location.kind && $0.path == location.path }
        }
        return result
    }

    public func recognizes(_ executable: String) -> Bool {
        programs.contains { $0.executables.contains(executable) }
    }
}
