/// Tool work as one sentence of counts, for a line that stands for several calls: "Read 3 files,
/// edited 2 files and ran 4 commands". Every call counts however it ended (the line's outcome word
/// says when the last one didn't succeed), except edits that didn't happen.
public struct ToolWorkSummary: Hashable, Sendable {
    /// What a summary counts, in the order a sentence names them.
    public enum Work: CaseIterable, Hashable, Sendable {
        case read, list, search, webSearch, fetch, edit, command, subagent, tool, plan
    }

    /// At most this many kinds of work are named; the rest are "other calls".
    static let namedKinds = 3

    /// How many of each kind of work, files counted once however often they were read or edited.
    public private(set) var counts: [Work: Int] = [:]
    /// How many calls of each kind, for "made 2 other calls".
    private var calls: [Work: Int] = [:]

    public init(calls: some Sequence<ToolCallState>) {
        var files: [Work: Set<String>] = [:]
        for call in calls where !call.isPolling {
            let wording = call.wording
            // An edit that failed or was refused changed nothing, so it isn't counted as one.
            guard wording.category != .edit || call.status == .completed || !call.status.isFinished else { continue }
            let work = Work(call, wording: wording)
            self.calls[work, default: 0] += 1
            switch work {
            case .read, .edit:
                files[work, default: []].formUnion(call.touchedPaths(wording))
            default:
                counts[work, default: 0] += 1
            }
        }
        for (work, paths) in files {
            counts[work] = max(paths.count, 1)
        }
    }

    /// The sentence, or nil when there are no calls.
    public var sentence: String? {
        let present = Work.allCases.filter { counts[$0] != nil }
        guard !present.isEmpty else { return nil }
        // Changes matter most, then commands, then what was looked at.
        let named = Set(present.sorted { $0.priority < $1.priority }.prefix(Self.namedKinds))
        var phrases = present.filter(named.contains).compactMap { work in counts[work].map(work.phrase) }
        let others = present.filter { !named.contains($0) }.reduce(0) { $0 + (calls[$1] ?? 0) }
        if others > 0 { phrases.append("made \(others) other \(others == 1 ? "call" : "calls")") }
        let sentence =
            phrases.count > 1
            ? phrases.dropLast().joined(separator: ", ") + " and " + (phrases.last ?? "") : phrases[0]
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// The glyph-level kind all the calls share, nil when they're mixed.
    public static func sharedCategory(of calls: some Sequence<ToolCallState>) -> ToolCategory? {
        var shared: ToolCategory?
        for call in calls where !call.isPolling {
            let category = call.wording.category
            if shared == nil { shared = category } else if shared != category { return nil }
        }
        return shared
    }
}

extension ToolWorkSummary.Work {
    init(_ call: ToolCallState, wording: ToolCallWording) {
        switch call.name {
        case "LS": self = .list
        case "WebSearch": self = .webSearch
        case "WebFetch": self = .fetch
        case "TodoWrite", "ExitPlanMode", "EnterPlanMode": self = .plan
        default:
            switch wording.category {
            case .read: self = wording.verb == .list ? .list : .read
            case .search: self = .search
            case .edit: self = .edit
            case .command: self = .command
            case .web: self = wording.verb == .fetch ? .fetch : .webSearch
            case .subagent: self = .subagent
            case .think: self = .plan
            case .mcp, .other: self = .tool
            }
        }
    }

    fileprivate var priority: Int {
        switch self {
        case .edit: 0
        case .command: 1
        case .read: 2
        case .search: 3
        case .webSearch: 4
        case .fetch: 5
        case .subagent: 6
        case .tool: 7
        case .list: 8
        case .plan: 9
        }
    }

    fileprivate func phrase(_ count: Int) -> String {
        func counted(_ singular: String, _ plural: String) -> String {
            "\(count) \(count == 1 ? singular : plural)"
        }
        return switch self {
        case .read: "read \(counted("file", "files"))"
        case .list: "listed \(counted("folder", "folders"))"
        case .search: count == 1 ? "searched once" : "searched \(count) times"
        case .webSearch: count == 1 ? "searched the web" : "searched the web \(count) times"
        case .fetch: "fetched \(counted("page", "pages"))"
        case .edit: "edited \(counted("file", "files"))"
        case .command: "ran \(counted("command", "commands"))"
        case .subagent: "started \(counted("subagent", "subagents"))"
        case .tool: "used \(counted("tool", "tools"))"
        case .plan: "updated the plan"
        }
    }
}

extension ToolCallState {
    /// The files a read or an edit touched, so reading one file twice counts it once.
    func touchedPaths(_ wording: ToolCallWording) -> Set<String> {
        let diffs = content.compactMap { content -> String? in
            if case .diff(let diff) = content { diff.path } else { nil }
        }
        if !diffs.isEmpty { return Set(diffs) }
        let path =
            rawInput?["file_path"]?.stringValue ?? rawInput?["notebook_path"]?.stringValue ?? locations.first?.path
        if let path { return [path] }
        return wording.files.isEmpty ? [wording.detail ?? wording.object] : Set(wording.files)
    }
}
