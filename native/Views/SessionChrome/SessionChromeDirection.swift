#if DEBUG
import Foundation

/// Where the session screen's tools live: a DEBUG-only prototype for choosing a direction, picked
/// with `-sessionChrome a|b|c|d`. Without the argument the session screen is today's.
enum SessionChromeDirection: String, CaseIterable {
    /// One side panel, a tab per tool.
    case sidePanel = "a"
    /// One workbench under the conversation; every terminal, run and tool is a tab in its strip.
    case workbench = "b"
    /// The header as a line of live facts, each opening its tool over the conversation.
    case facts = "c"
    /// The user puts each tool in the header, the side panel or the workbench, or turns it off.
    case arrangement = "d"

    /// The direction this launch asked for, if any.
    static let launchChoice: Self? = UserDefaults.standard.string(forKey: "sessionChrome").flatMap(Self.init(rawValue:))

    /// The places a tool can go in this direction; the others have one place each.
    var places: [SessionChromePlace] {
        switch self {
        case .sidePanel: [.side]
        case .workbench: [.bottom]
        case .facts: [.header]
        case .arrangement: SessionChromePlace.allCases
        }
    }

    /// The arrangement a launch starts with. `-sessionChromeArrangement custom` shows D's
    /// customized example instead of its default.
    var initialArrangement: SessionChromeArrangement {
        switch self {
        case .sidePanel: .sidePanel
        case .workbench: .workbench
        case .facts: .facts
        case .arrangement:
            UserDefaults.standard.string(forKey: "sessionChromeArrangement") == "custom" ? .composedCustom : .composed
        }
    }
}
#endif
