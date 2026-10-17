import Foundation

/// The plan a crew works through: legs in order, each a set of assignments that ends at a
/// checkpoint. The lead proposes it, the user edits and approves it, and from then on it's the
/// contract: only Native changes it, from the lead's revisions or the user's edits.
public nonisolated struct Route: Codable, Hashable, Sendable {
    /// How the lead means to approach the objective, in a few sentences.
    public var summary: String
    public var legs: [Leg]
    /// What the lead wants the user to settle before work starts. Answers travel with every brief.
    public var questions: [Question]
    public var assumptions: [String]

    public init(summary: String, legs: [Leg], questions: [Question] = [], assumptions: [String] = []) {
        self.summary = summary
        self.legs = legs
        self.questions = questions
        self.assumptions = assumptions
    }

    /// A stretch of the route: what's true once it's done, and the work that gets it there.
    public struct Leg: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var outcome: String
        public var assignments: [Assignment]

        public init(id: String, title: String, outcome: String, assignments: [Assignment]) {
            self.id = id
            self.title = title
            self.outcome = outcome
            self.assignments = assignments
        }
    }

    /// One piece of work for one crew member.
    public struct Assignment: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// What to do, where, and what to watch out for.
        public var brief: String
        /// How the builder, and the reviewer after it, know it's finished.
        public var doneWhen: [String]
        /// The agent it runs on (`WorkflowAgent.id`).
        public var assignee: String
        /// Assignments in the same or an earlier leg that must be done first.
        public var after: [String]
        /// For a fix round: the assignment whose session it continues, so the builder keeps its
        /// context. Nil for work from the route, which starts fresh.
        public var continues: String?

        public init(
            id: String, title: String, brief: String, doneWhen: [String], assignee: String, after: [String] = [],
            continues: String? = nil
        ) {
            self.id = id
            self.title = title
            self.brief = brief
            self.doneWhen = doneWhen
            self.assignee = assignee
            self.after = after
            self.continues = continues
        }
    }

    public struct Question: Codable, Hashable, Sendable {
        public var text: String
        public var answer: String?

        public init(text: String, answer: String? = nil) {
            self.text = text
            self.answer = answer
        }
    }

    public var assignments: [Assignment] {
        legs.flatMap(\.assignments)
    }

    public func leg(containing assignment: String) -> Leg? {
        legs.first { $0.assignments.contains { $0.id == assignment } }
    }

    /// The questions the user answered, for briefs.
    public var answeredQuestions: [Question] {
        questions.filter { !($0.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Assignment ids that differ between this route and `other`: added, removed or changed.
    public func changedAssignments(since other: Route) -> Set<String> {
        let mine = Dictionary(assignments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let theirs = Dictionary(other.assignments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(mine.keys).union(theirs.keys).filter { mine[$0] != theirs[$0] }
    }
}
