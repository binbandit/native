import GitHub
import SwiftUI

/// A 12pt glyph for a pull request's CI: a check when
/// passing, an x when failing, a dot while pending. Hover shows the counts.
struct ChecksIndicator: View {
    let checks: CheckSummary
    /// Off where a hover card says more (a task's badge), so the two don't stack.
    var hasTooltip = true

    var body: some View {
        Group {
            switch checks.state {
            case .passing:
                Image(systemName: "checkmark")
                    .font(.system(size: DS.Size.navIcon - DS.Space.xxs, weight: .bold))
            case .failing:
                Image(systemName: "xmark")
                    .font(.system(size: DS.Size.navIcon - DS.Space.xxs, weight: .bold))
            case .pending:
                Circle()
                    .frame(width: DS.Space.sm, height: DS.Space.sm)
            }
        }
        .foregroundStyle(tint)
        .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
        .help(hasTooltip ? Self.summary(checks) : "")
        .accessibilityElement()
        .accessibilityLabel(Self.summary(checks))
    }

    private var tint: Color {
        switch checks.state {
        case .passing: .dsSuccess
        case .failing: .dsDanger
        case .pending: .dsWarning
        }
    }

    /// "1 failing, 9 passed" style, the problems first.
    static func summary(_ checks: CheckSummary) -> String {
        var parts: [String] = []
        if checks.failed > 0 { parts.append("\(checks.failed) failing") }
        if checks.pending > 0 { parts.append("\(checks.pending) pending") }
        if checks.passed > 0 { parts.append("\(checks.passed) passed") }
        if checks.skipped > 0 { parts.append("\(checks.skipped) skipped") }
        guard !parts.isEmpty else {
            return switch checks.state {
            case .passing: "Checks passed"
            case .failing: "Checks failed"
            case .pending: "Checks running"
            }
        }
        return "Checks: " + parts.joined(separator: ", ")
    }
}
