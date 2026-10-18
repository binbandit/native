import NativeAutomation
import NativeExpeditions
import SwiftUI

/// How expeditions read in Native's one set of status patterns: `TaskStatus` for glyphs and
/// `Badge` tones, the same everywhere an expedition or a seat shows.
extension ExpeditionPhase {
    var taskStatus: TaskStatus {
        switch self {
        case .planning, .underway, .debriefing: .working
        case .reviewing: .needsPlanReview
        case .paused: .paused
        case .needsYou: .needsInput
        case .limited: .limited
        case .complete: .done
        case .stopped: .cancelled
        }
    }

    var tone: Badge.Tone {
        switch self {
        case .planning, .underway, .debriefing: .accent
        case .reviewing, .needsYou: .attention
        case .paused, .stopped: .neutral
        case .limited: .warning
        case .complete: .success
        }
    }
}

extension WorkflowStepStatus {
    var expeditionTaskStatus: TaskStatus {
        switch self {
        case .waiting, .skipped: .idle
        case .awaitingApproval: .needsPlanReview
        case .starting: .starting
        case .running: .working
        case .paused: .paused
        case .blocked: .needsInput
        case .limited: .limited
        case .failed, .interrupted: .failed
        case .cancelled: .cancelled
        case .succeeded: .done
        }
    }

    /// The progress bar's color for a seat in this state.
    var segmentColor: Color {
        switch self {
        case .succeeded: .dsSuccess
        case .skipped, .waiting: .dsSelected
        case .starting, .running: .dsAccent
        case .awaitingApproval, .blocked: .dsAttention
        case .paused, .cancelled: .dsTextQuaternary
        case .limited, .interrupted: .dsWarningFill
        case .failed: .dsDanger
        }
    }
}

extension Expedition {
    /// The line under the title: project, branch folder, age, cost against budget, working time.
    func metaLine(now: Date) -> String {
        var parts = [project.lastPathComponent]
        if let base, base != project {
            parts.append(base.lastPathComponent)
        }
        let age = DSFormat.compactAge(createdAt, now: now)
        parts.append(age == "now" ? "started just now" : "started \(age) ago")
        if let cost {
            parts.append(budget.maxCost.map { "\(DSFormat.cost(cost)) of \(DSFormat.cost($0))" } ?? DSFormat.cost(cost))
        } else if let max = budget.maxCost {
            parts.append("budget \(DSFormat.cost(max))")
        }
        let active = activeTime(at: now)
        if active >= 1 {
            parts.append("\(DSFormat.duration(active)) working")
        }
        return parts.joined(separator: " · ")
    }

    var progressText: String {
        guard let route else { return phase == .planning ? "Planning the route" : "No route yet" }
        guard approvedAt != nil else {
            return "\(route.assignments.count) \(route.assignments.count == 1 ? "assignment" : "assignments") proposed"
        }
        let count = assignments.filter { !$0.isFix }.count
        let finished = assignments.filter { !$0.isFix && $0.status.isFinished }.count
        let leg =
            currentLeg.flatMap { leg in route.legs.firstIndex { $0.id == leg.id } }.map {
                " · leg \($0 + 1) of \(route.legs.count)"
            } ?? ""
        return "\(finished) of \(count) assignments\(leg)"
    }

    /// What a seat is for, in a word.
    func role(of slot: CrewSlot) -> String {
        switch slot {
        case .lead: "Lead"
        case .assignment(let id): assignment(id)?.isFix == true ? "Fixes" : "Builder"
        case .checkpoint: "Reviewer"
        }
    }

    func title(of slot: CrewSlot) -> String {
        switch slot {
        case .lead: "Lead"
        case .assignment(let id): assignment(id)?.assignment.title ?? id
        case .checkpoint(let leg): "Checkpoint: \(self.leg(leg)?.title ?? leg)"
        }
    }
}
