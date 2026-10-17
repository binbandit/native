import Foundation
import NativeAutomation

/// What Native says to each member of the crew. Everything an agent needs is in its prompt, and
/// everything it hands back comes in its reply, so no agent ever has to write Native's files.
public nonisolated enum ExpeditionPrompt {
    /// The most of one report or reply that goes into another prompt.
    static let reportLimit = 4_000

    // MARK: - Lead

    static func planning(_ expedition: Expedition) -> String {
        """
        You're leading an expedition in Native: a crew of coding agents working through one large objective \
        together. Right now your job is to plan the route. Read whatever you need, but don't change any files yet.

        The objective, in the user's words:
        \(expedition.objective)

        \(crewLines(expedition))

        How the route works:
        - Legs run in order. Each leg ends at a checkpoint, where the reviewer checks the leg's outcome and every \
        assignment's "done when" criteria before the crew moves on.
        - An assignment is one builder's work in one fresh session: something a capable engineer finishes in an \
        hour or two, with a clear brief and criteria someone else can check.
        - Builders share this folder and, by default, work one at a time, so order the work sensibly and use \
        "after" only for real dependencies within a leg or on earlier legs.
        - A builder sees the objective, your summary, its brief, the user's answers and the reports of the \
        assignments it comes after, nothing else. Put everything an assignment needs in its brief.\(budgetLine(expedition))

        When you're ready, end your reply with the route as JSON between \(RouteParser.openTag) and \(RouteParser.closeTag):
        \(RouteParser.openTag)
        {
          "summary": "How you'll approach the objective, in two to four sentences.",
          "legs": [
            {
              "title": "A short name for the leg",
              "outcome": "What's true once this leg is done",
              "assignments": [
                {
                  "id": "short-kebab-id",
                  "title": "Imperative title",
                  "brief": "What to do, where, and what to watch out for",
                  "doneWhen": ["A criterion someone can check"],
                  "assignee": "\(expedition.crew.builders.first?.id ?? "agent-id")",
                  "after": []
                }
              ]
            }
          ],
          "questions": ["Only what you can't reasonably decide yourself"],
          "assumptions": ["Choices you made that the user should know about"]
        }
        \(RouteParser.closeTag)
        """
    }

    static func revision(feedback: String) -> String {
        """
        The user reviewed your route and asked for changes:

        \(feedback)

        Revise the route, then end your reply with the whole revised route between \(RouteParser.openTag) and \
        \(RouteParser.closeTag), in the same shape as before.
        """
    }

    static func routeProblem(_ problem: String) -> String {
        """
        Native couldn't read your route: \(problem)

        Send the whole route again, as JSON between \(RouteParser.openTag) and \(RouteParser.closeTag), in the shape \
        from the planning message.
        """
    }

    static func legReview(_ expedition: Expedition, passed leg: Route.Leg) -> String {
        let ahead = expedition.route?.legs.drop { $0.id != leg.id }.dropFirst() ?? []
        let legsAhead = ahead.map { leg in
            "- \(leg.title): \(leg.outcome)\n" + leg.assignments.map { "  - \($0.id): \($0.title) (\($0.assignee))" }.joined(separator: "\n")
        }
        return """
            The leg "\(leg.title)" passed its checkpoint\(expedition.checkpoint(leg.id)?.latestVerdict?.note.map { ": \($0)" } ?? ".")

            What the builders reported:
            \(reports(expedition, in: leg.id))

            The legs ahead:
            \(legsAhead.joined(separator: "\n"))

            If what you've learned changes the legs ahead, end your reply with just those legs, revised, as JSON \
            between \(RouteParser.openTag) and \(RouteParser.closeTag) in the route's shape. Keep the ids of \
            assignments you don't change. If they're still right, say so in a sentence, with no route block. \
            Don't change any files.
            """
    }

    static func debrief(_ expedition: Expedition) -> String {
        let legs = (expedition.route?.legs ?? []).map { leg in
            let verdict = expedition.checkpoint(leg.id).map { checkpoint in
                checkpoint.status == .skipped ? "not checked" : (checkpoint.latestVerdict?.note ?? checkpoint.status.label)
            } ?? ""
            return "## \(leg.title) (\(verdict))\n" + reports(expedition, in: leg.id)
        }
        return """
            \(expedition.isWrappingUp ? "The user asked to wrap up, so the work below is what got done." : "Every leg of the route is done.")

            \(legs.joined(separator: "\n\n"))

            First commit anything still uncommitted in this folder, with a clear message. Then write the debrief: a \
            one-paragraph summary, what was done leg by leg, what the checkpoints verified, and anything left undone, \
            follow-ups or risks. It becomes the pull request's description, so write it in Markdown for a reviewer. \
            Reply with the debrief only.
            """
    }

    // MARK: - Builders

    /// What the goal keeps the builder working toward. Short, because it's restated every turn.
    static func assignmentGoal(_ run: AssignmentRun) -> String {
        let criteria = run.assignment.doneWhen.map { "- \($0)" }.joined(separator: "\n")
        return "Finish the assignment \"\(run.assignment.title)\". Done when:\n\(criteria)"
    }

    /// The context a builder gets with its first prompt, before the goal.
    static func assignmentBriefing(_ expedition: Expedition, _ run: AssignmentRun) -> String {
        let leg = expedition.leg(run.leg)
        var sections = [
            """
            You're a builder on an expedition in Native: a crew of agents working through an approved route, \
            coordinated by Native. This session is for one assignment; other crew members handle the rest.

            The expedition's objective:
            \(expedition.objective)
            """
        ]
        if let summary = expedition.route?.summary.nilIfEmpty {
            sections.append("The approach:\n\(summary)")
        }
        if let leg {
            sections.append("This leg, \"\(leg.title)\": \(leg.outcome)")
        }
        sections.append("Your assignment, \"\(run.assignment.title)\":\n\(run.assignment.brief)")
        let answers = expedition.route?.answeredQuestions ?? []
        if !answers.isEmpty {
            sections.append("The user's answers:\n" + answers.map { "- \($0.text) \($0.answer ?? "")" }.joined(separator: "\n"))
        }
        if let assumptions = expedition.route?.assumptions, !assumptions.isEmpty {
            sections.append("Assumptions in the route:\n" + assumptions.map { "- \($0)" }.joined(separator: "\n"))
        }
        let before = run.assignment.after.compactMap(expedition.assignment)
        if !before.isEmpty {
            sections.append("What came before:\n" + before.map { report(expedition, $0) }.joined(separator: "\n\n"))
        }
        sections.append(
            "Work in this folder and stay within your assignment. When it's done, commit your changes with a clear message, "
                + "then say what you changed and how you verified it.")
        return sections.joined(separator: "\n\n")
    }

    static func fixGoal(leg: Route.Leg) -> String {
        "Address the reviewer's findings for the leg \"\(leg.title)\", so that: \(leg.outcome)"
    }

    static func fixBriefing(_ expedition: Expedition, leg: Route.Leg, verdict: CheckpointVerdict, round: Int) -> String {
        """
        The reviewer checked the leg "\(leg.title)" and asked for changes (round \(round)):

        \(verdict.findings.nilIfEmpty.map { String($0.prefix(reportLimit)) } ?? verdict.note ?? "No details.")

        Fix these in this folder, commit the fixes with a clear message, then say what you changed. The reviewer \
        checks again when you're done.
        """
    }

    static let interrupted = """
        Your previous turn was cut off before it finished. Check the current state before you continue (for \
        example, re-read files you were changing), then carry on. If it was already done, say so briefly.
        """

    static func failed(_ message: String) -> String {
        """
        Your previous turn failed: \(message). Check the current state before you continue (for example, re-read \
        files you were changing), then carry on.
        """
    }

    // MARK: - Reviewer

    static func checkpoint(_ expedition: Expedition, leg: Route.Leg) -> String {
        """
        You're the reviewer on an expedition in Native: a crew of agents working through an approved route. The \
        builders have finished the leg "\(leg.title)"; check it before the crew moves on. Review only: don't change \
        any files.

        The expedition's objective:
        \(expedition.objective)

        This leg's outcome: \(leg.outcome)

        What was asked, and what the builders reported:
        \(expedition.assignments(in: leg.id).filter { !$0.isFix }.map { run in
            "### \(run.assignment.title)\nDone when:\n" + run.assignment.doneWhen.map { "- \($0)" }.joined(separator: "\n")
                + "\nReport:\n" + (run.status == .skipped ? "(skipped by the user)" : String((run.report ?? "(no report)").prefix(reportLimit)))
        }.joined(separator: "\n\n"))

        Check the work in this folder: read the changes (git log and git diff help), run the tests, and anything \
        else that shows whether each criterion holds. Be concrete about problems: name files and what's wrong.

        End your reply with one verdict line, on a line of its own:
        \(CheckpointVerdict.protocolLines)
        When you ask for changes, list every problem above the verdict line.
        """
    }

    static func recheck(_ expedition: Expedition, leg: Route.Leg, fix: AssignmentRun?) -> String {
        """
        The builder addressed your findings for "\(leg.title)". It reported:

        \(String((fix?.report ?? "(no report)").prefix(reportLimit)))

        Check the leg again against the same criteria, then end your reply with one verdict line:
        \(CheckpointVerdict.protocolLines)
        """
    }

    static let verdictReminder = """
        Your last reply didn't end with a verdict line, so Native couldn't tell whether the leg passed. End your \
        reply with one of:
        \(CheckpointVerdict.protocolLines)
        """

    // MARK: - Parts

    private static func crewLines(_ expedition: Expedition) -> String {
        let crew = expedition.crew
        let builders = crew.builders.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        return """
            The crew. Builders (use these ids as assignees; match work to their strengths):
            \(builders)
            The reviewer, \(crew.reviewer.name), checks each leg. You, \(crew.lead.name), lead.
            """
    }

    private static func budgetLine(_ expedition: Expedition) -> String {
        var parts: [String] = []
        if let cost = expedition.budget.maxCost {
            parts.append(ExpeditionBudget.costText(cost))
        }
        if let duration = expedition.budget.maxDuration {
            parts.append("\(ExpeditionBudget.durationText(duration)) of working time")
        }
        return parts.isEmpty ? "" : "\n- The budget for the whole expedition is \(parts.joined(separator: " and ")); plan for it."
    }

    static func reports(_ expedition: Expedition, in leg: String) -> String {
        let runs = expedition.assignments(in: leg)
        return runs.isEmpty ? "(none)" : runs.map { report(expedition, $0) }.joined(separator: "\n\n")
    }

    private static func report(_ expedition: Expedition, _ run: AssignmentRun) -> String {
        let body = run.status == .skipped ? "(skipped)" : String((run.report ?? run.latestReply ?? "(no report)").prefix(reportLimit))
        return "### \(run.assignment.title) (\(expedition.crew.agent(run.assignment.assignee)?.name ?? run.assignment.assignee))\n\(body)"
    }
}
