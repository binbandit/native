import Foundation

/// The model rows a settings popover shows for one query, in the agent's order. A short list shows
/// whole; past `filterThreshold` a filter takes the header's place and the list keeps a fixed number
/// of slots, so the popover never changes height while someone types. Names show as the agent sent
/// them; the value Native sends back shows only where it tells two rows apart or is what matched.
public struct ModelChoiceList: Equatable, Sendable {
    public typealias Choice = ConfigOption.SelectOption

    /// Lists longer than this get the filter.
    public static let filterThreshold = 8
    /// Row slots a filtered list keeps.
    public static let slots = 6
    /// A description short enough to tell two same-named rows apart ("1M context", "From gateway").
    static let shortDescription = 24

    public struct Row: Equatable, Sendable, Identifiable {
        public let choice: Choice
        public let name: String
        /// Where the query matched the name, for drawing those characters heavier.
        public let nameMatches: [Range<String.Index>]
        public let detail: Detail?

        public var id: String { choice.value }
    }

    public enum Detail: Equatable, Sendable {
        /// A plain note: what Default runs now, or what sets a row apart from one with its name.
        case note(String)
        /// The value, shown because it's what sets the row apart or what the query matched.
        case value(String, matches: [Range<String.Index>])
    }

    public let rows: [Row]
    /// Matches past the last row, said in the last slot ("4 more match").
    public let overflow: Int
    /// Whether the list is long enough for the filter.
    public let isFilterable: Bool
    public let query: String

    /// - Parameters:
    ///   - choices: The agent's models, in its order (first of each value, `uniqued`).
    ///   - current: The value the session runs on, kept in view when the filter is empty.
    ///   - slots: Row slots for a filterable list; fewer when the popover runs out of height.
    public init(
        choices: [Choice], current: String, query: String = "", slots: Int = Self.slots,
        searchTerms: [String: [String]] = [:], forceFilter: Bool = false
    ) {
        let choices = choices.uniqued
        isFilterable = forceFilter || choices.count > Self.filterThreshold
        self.query = isFilterable ? query : ""
        let words = Self.words(in: self.query)
        let duplicates = Dictionary(grouping: choices, by: \.displayName).filter { $0.value.count > 1 }

        func row(_ choice: Choice, valueMatches: [Range<String.Index>]? = nil) -> Row {
            let name = choice.displayName
            let detail: Detail? =
                if let valueMatches {
                    .value(choice.value, matches: valueMatches)
                } else if let group = duplicates[name] {
                    Self.distinction(of: choice, among: group)
                } else {
                    choice.resolvedDefault.map(Detail.note)
                }
            return Row(choice: choice, name: name, nameMatches: Self.ranges(of: words, in: name), detail: detail)
        }

        guard isFilterable else {
            rows = choices.map { row($0) }
            overflow = 0
            return
        }
        guard !words.isEmpty else {
            var shown = Array(choices.prefix(slots))
            if !shown.contains(where: { $0.value == current }),
                let currentChoice = choices.first(where: {
                    $0.value == current
                })
            {
                shown[shown.count - 1] = currentChoice
            }
            rows = shown.map { row($0) }
            overflow = 0
            return
        }
        let matches: [Row] = choices.compactMap { choice in
            if Self.contains(words, in: choice.displayName) { return row(choice) }
            if Self.contains(words, in: choice.value) {
                return row(choice, valueMatches: Self.ranges(of: words, in: choice.value))
            }
            if searchTerms[choice.value]?.contains(where: { Self.contains(words, in: $0) }) == true {
                return row(choice)
            }
            return nil
        }
        if matches.count > slots {
            rows = Array(matches.prefix(slots - 1))
            overflow = matches.count - rows.count
        } else {
            rows = matches
            overflow = 0
        }
    }

    /// A same-named choice's distinction, using original adapter values, before a client gives
    /// rows a combined identity across adapters.
    public static func distinguishingDetail(for choice: Choice, among choices: [Choice]) -> Detail? {
        let group = choices.filter { $0.displayName == choice.displayName }
        guard group.count > 1 else { return nil }
        return distinction(of: choice, among: group)
    }

    /// What tells `choice` apart from the others with its name: its description when that's short and
    /// no other has it, else its value.
    private static func distinction(of choice: Choice, among group: [Choice]) -> Detail? {
        let others = group.filter { $0.value != choice.value }
        if !others.contains(where: { $0.description == choice.description }) {
            guard let description = choice.description else { return nil }
            if description.count <= shortDescription { return .note(description) }
        }
        return .value(choice.value, matches: [])
    }

    private static func words(in query: String) -> [Substring] {
        query.split(whereSeparator: \.isWhitespace)
    }

    private static func contains(_ words: [Substring], in text: String) -> Bool {
        words.allSatisfy { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func ranges(of words: [Substring], in text: String) -> [Range<String.Index>] {
        words.compactMap { text.range(of: $0, options: .caseInsensitive) }
    }
}

extension ConfigOption.SelectOption {
    /// The name without the agent's "(recommended)" aside.
    public var displayName: String {
        let name = name.replacing(/\s*\(recommended\)\s*$/.ignoresCase(), with: "")
        return name.isEmpty ? self.name : name
    }

    /// For the agent's "default" model, the model it runs now, when its description is just that name
    /// (Claude Code's "Opus"); nil for every other choice.
    public var resolvedDefault: String? {
        guard value == "default", let description, !description.isEmpty, !description.contains("·"),
            description != displayName
        else { return nil }
        return description
    }

    /// The description without the name the agent repeats at its start ("Haiku 5.5 · Fastest for
    /// quick answers"); nil when it says nothing the name doesn't.
    public var purpose: String? {
        guard let description, description != name, description != displayName else { return nil }
        let prefix = "\(displayName) · "
        return description.hasPrefix(prefix) ? String(description.dropFirst(prefix.count)) : description
    }
}

extension Array where Element == ConfigOption.SelectOption {
    /// The first choice of each value: a long gateway list can repeat one, and a value is what
    /// identifies a choice (what Native sends back, and a row's identity).
    public var uniqued: [Element] {
        var seen = Set<String>()
        return filter { seen.insert($0.value).inserted }
    }
}
