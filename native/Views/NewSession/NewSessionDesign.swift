import Foundation

/// Which empty state a new session shows. Three candidate designs are under review; until one is
/// picked, users see today's, and Debug builds can show another with `-newSessionDesign a|b|c`.
nonisolated enum NewSessionDesign: String, Sendable {
    /// The centered prompt over the folder path.
    case today
    /// Quiet focus: the project set large above the composer, with one line of exact context.
    case focus = "a"
    /// Workbench: the project's state, then tasks and pull requests to continue from.
    case workbench = "b"
    /// Starting points: a short ledger of real ways to begin.
    case startingPoints = "c"

    /// Read once per launch, so the empty state never reads defaults on the "+" path.
    static let current: NewSessionDesign = {
        #if DEBUG
        UserDefaults.standard.string(forKey: "newSessionDesign").flatMap(NewSessionDesign.init(rawValue:)) ?? .today
        #else
        .today
        #endif
    }()
}
