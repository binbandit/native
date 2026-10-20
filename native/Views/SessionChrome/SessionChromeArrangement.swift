#if DEBUG && NATIVE_SESSION_CHROME_WIP
/// The places on the session screen a tool can live.
enum SessionChromePlace: String, CaseIterable, Identifiable {
    /// A live fact in the header, under the title; the tool opens over the conversation.
    case header
    /// A tab in the panel beside the conversation.
    case side
    /// A tab in the workbench under the conversation and composer.
    case bottom

    var id: Self { self }

    var title: String {
        switch self {
        case .header: "Header"
        case .side: "Side panel"
        case .bottom: "Workbench"
        }
    }

    var summary: String {
        switch self {
        case .header: "A fact under the title. Opens over the conversation."
        case .side: "A tab beside the conversation."
        case .bottom: "A tab under the composer."
        }
    }
}

/// Which tools live where. A tool lives in one place at most; a tool in none is off.
struct SessionChromeArrangement: Equatable {
    private var places: [SessionChromePlace: [SessionChromeTool]]

    init(header: [SessionChromeTool] = [], side: [SessionChromeTool] = [], bottom: [SessionChromeTool] = []) {
        places = [.header: header, .side: side, .bottom: bottom]
    }

    func tools(in place: SessionChromePlace) -> [SessionChromeTool] {
        places[place] ?? []
    }

    func place(of tool: SessionChromeTool) -> SessionChromePlace? {
        SessionChromePlace.allCases.first { tools(in: $0).contains(tool) }
    }

    var off: [SessionChromeTool] {
        SessionChromeTool.allCases.filter { place(of: $0) == nil }
    }

    mutating func move(_ tool: SessionChromeTool, to place: SessionChromePlace?) {
        for key in SessionChromePlace.allCases {
            places[key]?.removeAll { $0 == tool }
        }
        if let place {
            places[place, default: []].append(tool)
        }
    }

    /// A: every tool a tab in the side panel.
    static let sidePanel = Self(side: [.changes, .terminal, .run, .agents, .pullRequest, .openIn])
    /// B: every tool a tab in the workbench.
    static let workbench = Self(bottom: [.terminal, .changes, .run, .agents, .pullRequest, .openIn])
    /// C: every tool a fact in the header, the branch first.
    static let facts = Self(header: [.pullRequest, .changes, .run, .terminal, .agents, .openIn])
    /// D's default: what you read beside the conversation, what you type into under it, and what
    /// you only glance at as a fact.
    static let composed = Self(header: [.run, .openIn], side: [.changes, .agents, .pullRequest], bottom: [.terminal])
    /// D customized, a reviewer's arrangement: diffs wide in the workbench, a shell beside the
    /// conversation, runs as a fact, and subagents, pull requests and Open In turned off.
    static let composedCustom = Self(header: [.run], side: [.terminal], bottom: [.changes])
}
#endif
