import Foundation

/// Reads the `<route>` block a lead ends its planning reply with. Forgiving about how it's wrapped
/// (code fences, prose around it, missing optional fields, ids it left out) and strict about what
/// the engine relies on: at least one assignment, unique ids, `after` naming work that comes
/// earlier, no cycles. Anything wrong comes back as a problem worded for the lead, which gets it to
/// fix the route itself.
public nonisolated enum RouteParser {
    public struct Problem: Error, Hashable, Sendable {
        public var message: String

        public init(_ message: String) {
            self.message = message
        }
    }

    public static let openTag = "<route>"
    public static let closeTag = "</route>"

    /// Whether `reply` has a route block at all, parsed or not.
    public static func containsRoute(_ reply: String) -> Bool {
        reply.range(of: openTag, options: [.caseInsensitive, .backwards]) != nil
    }

    /// The route in `reply`, with assignees outside `builders` moved onto them in turn. `earlier`
    /// names assignments from legs before the ones in `reply`, which its work may come after.
    public static func parse(_ reply: String, builders: [String], earlier: Set<String> = []) -> Result<Route, Problem> {
        guard let json = block(in: reply) else {
            return .failure(Problem("Your reply has no \(openTag) block. End it with the route as JSON inside \(openTag) and \(closeTag)."))
        }
        let wire: WireRoute
        do {
            wire = try JSONDecoder().decode(WireRoute.self, from: Data(json.utf8))
        } catch {
            return .failure(Problem("The \(openTag) block isn't valid JSON in the expected shape: \(describe(error))"))
        }
        return validate(wire, builders: builders, earlier: earlier)
    }

    /// The JSON between the last route tags, without code fences.
    static func block(in reply: String) -> String? {
        guard let open = reply.range(of: openTag, options: [.caseInsensitive, .backwards]) else { return nil }
        let rest = reply[open.upperBound...]
        let body = rest.range(of: closeTag, options: .caseInsensitive).map { rest[..<$0.lowerBound] } ?? rest
        var lines = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        lines.removeAll { $0.hasPrefix("```") }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Prose the lead wrapped around the object stays out; without an object, the decoder says
        // what's wrong.
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }

    private static func validate(_ wire: WireRoute, builders: [String], earlier known: Set<String>) -> Result<Route, Problem> {
        var seen = known
        var earlier = known
        var legs: [Route.Leg] = []
        var nextBuilder = 0
        for (legIndex, wireLeg) in (wire.legs ?? []).enumerated() {
            let legTitle = wireLeg.title?.trimmed ?? "Leg \(legIndex + 1)"
            var assignments: [Route.Assignment] = []
            for (index, item) in (wireLeg.assignments ?? []).enumerated() {
                guard let title = item.title?.trimmed, !title.isEmpty else {
                    return .failure(Problem("Assignment \(index + 1) in \"\(legTitle)\" has no title."))
                }
                var id = slug(item.id?.trimmed ?? "").nilIfEmpty ?? slug(title).nilIfEmpty ?? "assignment-\(seen.count + 1)"
                if seen.contains(id) {
                    guard item.id == nil else { return .failure(Problem("Two assignments have the id \"\(id)\"; give each its own.")) }
                    id = unique(id, in: seen)
                }
                seen.insert(id)
                var assignee = item.assignee?.trimmed ?? ""
                if !builders.contains(assignee), !builders.isEmpty {
                    assignee = builders[nextBuilder % builders.count]
                    nextBuilder += 1
                }
                let doneWhen = (item.doneWhen ?? []).compactMap { $0.trimmed.nilIfEmpty }
                let brief = item.brief?.trimmed.nilIfEmpty ?? title
                assignments.append(Route.Assignment(
                    id: id, title: title, brief: brief, doneWhen: doneWhen.isEmpty ? [wireLeg.outcome?.trimmed.nilIfEmpty ?? legTitle] : doneWhen,
                    assignee: assignee, after: (item.after ?? []).map { slug($0.trimmed) }))
            }
            guard !assignments.isEmpty else { continue }
            let inLeg = Set(assignments.map(\.id))
            for assignment in assignments {
                for dependency in assignment.after where !earlier.contains(dependency) && !inLeg.contains(dependency) {
                    return .failure(Problem("\"\(assignment.title)\" comes after \"\(dependency)\", which isn't an assignment in its leg or an earlier one."))
                }
            }
            if let cycle = cycle(in: assignments) {
                return .failure(Problem("The assignments \(cycle.map { "\"\($0)\"" }.joined(separator: ", ")) wait for each other, so none could start."))
            }
            earlier.formUnion(inLeg)
            legs.append(Route.Leg(id: "leg-\(legs.count + 1)", title: legTitle, outcome: wireLeg.outcome?.trimmed ?? legTitle, assignments: assignments))
        }
        guard !legs.isEmpty else {
            return .failure(Problem("The route has no assignments. Give it at least one leg with at least one assignment."))
        }
        return .success(Route(
            summary: wire.summary?.trimmed ?? "",
            legs: legs,
            questions: (wire.questions ?? []).compactMap { $0.trimmed.nilIfEmpty }.map { Route.Question(text: $0) },
            assumptions: (wire.assumptions ?? []).compactMap { $0.trimmed.nilIfEmpty }
        ))
    }

    /// The first set of assignments in `assignments` that wait on each other within the leg.
    private static func cycle(in assignments: [Route.Assignment]) -> [String]? {
        var remaining = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, Set($0.after).intersection(assignments.map(\.id))) })
        while let free = remaining.first(where: { $0.value.isEmpty })?.key {
            remaining[free] = nil
            for key in remaining.keys {
                remaining[key]?.remove(free)
            }
        }
        return remaining.isEmpty ? nil : assignments.filter { remaining[$0.id] != nil }.map(\.title)
    }

    static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let words = text.lowercased().unicodeScalars.split { !allowed.contains($0) }.map { String(String.UnicodeScalarView($0)) }
        return words.prefix(6).joined(separator: "-")
    }

    private static func unique(_ id: String, in seen: Set<String>) -> String {
        var number = 2
        while seen.contains("\(id)-\(number)") {
            number += 1
        }
        return "\(id)-\(number)"
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "\(context.debugDescription) (at \(path(context.codingPath)))"
        case DecodingError.dataCorrupted(let context):
            context.debugDescription
        default:
            error.localizedDescription
        }
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        keys.isEmpty ? "the top level" : keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }

    // MARK: - Wire shape

    /// Everything optional: a missing field gets a default or a clear problem, never a decoding
    /// error the lead can't act on.
    private struct WireRoute: Decodable {
        var summary: String?
        var legs: [WireLeg]?
        var questions: [String]?
        var assumptions: [String]?
    }

    private struct WireLeg: Decodable {
        var title: String?
        var outcome: String?
        var assignments: [WireAssignment]?
    }

    private struct WireAssignment: Decodable {
        var id: String?
        var title: String?
        var brief: String?
        var doneWhen: [String]?
        var assignee: String?
        var after: [String]?
    }
}

extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
