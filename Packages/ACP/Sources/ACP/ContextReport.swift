import Foundation

/// What fills a session's context window, from Claude Code's `/context` report.
///
/// Claude Code answers the `/context` prompt locally, with no model call, as markdown: a
/// `## Context Usage` heading, the model and token totals, a category table, then tables of MCP
/// tools, custom agents, memory files and skills. Sections the agent has nothing for are left
/// out, and token counts come in its compact form (`103`, `2k`, `228.4k`, `1m`, `~300`, `< 20`).
public struct ContextReport: Hashable, Sendable {
    public var model: String?
    /// Estimated tokens in use; the agent rounds it to its compact form.
    public var usedTokens: Int
    /// The window usage is measured against: the model's limit or a smaller compaction window.
    public var windowTokens: Int
    /// Used share of the window as the agent rounds it, 0-100 (more when over the limit).
    public var percentage: Double
    /// The agent's note when usage is past the window, such as "run /compact to continue".
    public var overLimit: String?
    /// Every category row, in the agent's order.
    public var categories: [Category]
    public var mcpTools: [MCPTool]
    public var memoryFiles: [MemoryFile]
    public var skills: [Skill]
    public var agents: [CustomAgent]
    /// When the report was taken, so a client can tell how fresh it is.
    public var capturedAt: Date

    public init(
        model: String?, usedTokens: Int, windowTokens: Int, percentage: Double, overLimit: String? = nil,
        categories: [Category] = [], mcpTools: [MCPTool] = [], memoryFiles: [MemoryFile] = [],
        skills: [Skill] = [], agents: [CustomAgent] = [], capturedAt: Date = .now
    ) {
        self.model = model
        self.usedTokens = usedTokens
        self.windowTokens = windowTokens
        self.percentage = percentage
        self.overLimit = overLimit
        self.categories = categories
        self.mcpTools = mcpTools
        self.memoryFiles = memoryFiles
        self.skills = skills
        self.agents = agents
        self.capturedAt = capturedAt
    }

    public struct Category: Hashable, Sendable {
        /// What the row is, after the SDK's `SDKContextUsageCategory.kind`. The markdown doesn't carry
        /// it, so it's read from the row's name.
        public enum Kind: String, Hashable, Sendable {
            /// Content occupying the window.
            case used
            /// The rest of the window.
            case free
            /// Reserved for compaction.
            case buffer
            /// Tool schemas loaded on demand: listed for awareness, not counted.
            case deferred
        }

        public var name: String
        public var tokens: Int
        public var kind: Kind

        public init(name: String, tokens: Int, kind: Kind) {
            self.name = name
            self.tokens = tokens
            self.kind = kind
        }
    }

    public struct MCPTool: Hashable, Sendable {
        /// The wire name, such as `mcp__linear__create_issue`.
        public var name: String
        public var server: String
        public var tokens: Int

        public init(name: String, server: String, tokens: Int) {
            self.name = name
            self.server = server
            self.tokens = tokens
        }

        /// The name without its `mcp__<server>__` prefix.
        public var shortName: String {
            guard name.hasPrefix("mcp__") else { return name }
            let rest = name.dropFirst(5)
            guard let separator = rest.range(of: "__") else { return name }
            let short = rest[separator.upperBound...]
            return short.isEmpty ? name : String(short)
        }
    }

    /// An MCP server's tools, with their combined cost.
    public struct MCPServer: Hashable, Sendable, Identifiable {
        public var name: String
        /// Most expensive first.
        public var tools: [MCPTool]

        public var id: String { name }
        public var tokens: Int { tools.reduce(0) { $0 + $1.tokens } }
    }

    public struct MemoryFile: Hashable, Sendable {
        /// Where the file comes from, such as "User" or "Project".
        public var type: String
        public var path: String
        public var tokens: Int

        public init(type: String, path: String, tokens: Int) {
            self.type = type
            self.path = path
            self.tokens = tokens
        }
    }

    public struct Skill: Hashable, Sendable {
        public var name: String
        /// Where the skill comes from, such as "User", "Built-in" or "Plugin (code-review)".
        public var source: String
        /// The agent only estimates skills: `~300`, or `< 20` for the smallest.
        public var tokens: TokenCount

        public init(name: String, source: String, tokens: TokenCount) {
            self.name = name
            self.source = source
            self.tokens = tokens
        }
    }

    public struct CustomAgent: Hashable, Sendable {
        public var type: String
        /// Such as "Project", "User" or "Plugin".
        public var source: String
        public var tokens: Int

        public init(type: String, source: String, tokens: Int) {
            self.type = type
            self.source = source
            self.tokens = tokens
        }
    }

    /// A token count as the agent printed it.
    public struct TokenCount: Hashable, Sendable {
        public enum Bound: Hashable, Sendable {
            /// The value, as rounded by the agent's compact format.
            case exact
            /// About the value (`~300`).
            case approximate
            /// Under the value (`< 20`).
            case below
        }

        public var value: Int
        public var bound: Bound

        public init(_ value: Int, bound: Bound = .exact) {
            self.value = value
            self.bound = bound
        }
    }

    // MARK: - Derived

    public var usedCategories: [Category] { categories.filter { $0.kind == .used } }
    public var deferredCategories: [Category] { categories.filter { $0.kind == .deferred } }
    public var freeTokens: Int { categories.filter { $0.kind == .free }.reduce(0) { $0 + $1.tokens } }
    public var bufferTokens: Int { categories.filter { $0.kind == .buffer }.reduce(0) { $0 + $1.tokens } }

    public var fractionUsed: Double {
        windowTokens > 0 ? Double(usedTokens) / Double(windowTokens) : 0
    }

    /// MCP tools grouped by server, the most expensive server first.
    public var mcpServers: [MCPServer] {
        Dictionary(grouping: mcpTools, by: \.server)
            .map { MCPServer(name: $0.key, tools: $0.value.sorted { ($0.tokens, $1.name) > ($1.tokens, $0.name) }) }
            .sorted { ($0.tokens, $1.name) > ($1.tokens, $0.name) }
    }
}

// MARK: - Parsing

extension ContextReport {
    /// Reads the markdown Claude Code answers `/context` with. Returns nil when the text isn't a
    /// context report. Tolerates missing sections, and text holding the report more than once (the
    /// adapter can send it twice in one turn, as two messages): the last copy wins.
    public static func parse(_ markdown: String, capturedAt: Date = .now) -> ContextReport? {
        var text = Substring(markdown)
        if let start = markdown.range(of: "## Context Usage", options: .backwards) {
            text = markdown[start.lowerBound...]
        }

        var model: String?
        var totals: (used: Int, window: Int, percentage: Double)?
        var overLimit: String?
        var section: Section?
        var tables: [Section: [[String]]] = [:]
        var sawHeader: Set<Section> = []

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                section = Section(heading: line.dropFirst(4))
                continue
            }
            if line.hasPrefix("#") {
                section = nil
                continue
            }
            if let value = line.value(afterLabel: "Model") {
                model = value.isEmpty ? nil : value
            } else if let value = line.value(afterLabel: "Tokens") {
                totals = parseTotals(value)
            } else if let value = line.value(afterLabel: "Over limit") {
                overLimit = value
            } else if line.hasPrefix("|"), let section {
                let cells = line.tableCells
                // The first row of a table names its columns; the next only draws the rule.
                if cells.allSatisfy(\.isTableRule) { continue }
                if sawHeader.insert(section).inserted { continue }
                tables[section, default: []].append(cells)
            }
        }

        guard let totals else { return nil }
        let rows = { (section: Section) in tables[section] ?? [] }
        return ContextReport(
            model: model,
            usedTokens: totals.used,
            windowTokens: totals.window,
            percentage: totals.percentage,
            overLimit: overLimit,
            categories: rows(.categories).compactMap { category(from: $0, window: totals.window) },
            mcpTools: rows(.mcpTools).compactMap { cells in
                guard cells.count >= 3, let tokens = tokenCount(cells.last ?? "")?.value else { return nil }
                return MCPTool(name: cells[0], server: cells.middle, tokens: tokens)
            },
            memoryFiles: rows(.memoryFiles).compactMap { cells in
                guard cells.count >= 3, let tokens = tokenCount(cells.last ?? "")?.value else { return nil }
                return MemoryFile(type: cells[0], path: cells.middle, tokens: tokens)
            },
            skills: rows(.skills).compactMap { cells in
                guard cells.count >= 3, let tokens = tokenCount(cells.last ?? "") else { return nil }
                return Skill(name: cells[0], source: cells.middle, tokens: tokens)
            },
            agents: rows(.agents).compactMap { cells in
                guard cells.count >= 3, let tokens = tokenCount(cells.last ?? "")?.value else { return nil }
                return CustomAgent(type: cells[0], source: cells.middle, tokens: tokens)
            },
            capturedAt: capturedAt
        )
    }

    /// Reads a count in the agent's compact format: `103`, `2k`, `228.4k`, `1m`, `1,234`, `~300` or
    /// `< 20`.
    public static func tokenCount(_ text: String) -> TokenCount? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        var bound = TokenCount.Bound.exact
        if rest.hasPrefix("~") {
            bound = .approximate
            rest = rest.dropFirst()
        } else if rest.hasPrefix("<") {
            bound = .below
            rest = rest.dropFirst()
        }
        rest = Substring(rest.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
        var multiplier = 1.0
        switch rest.last?.lowercased() {
        case "k": multiplier = 1_000
        case "m": multiplier = 1_000_000
        case "b": multiplier = 1_000_000_000
        default: break
        }
        if multiplier != 1 {
            rest = rest.dropLast()
        }
        guard !rest.isEmpty, rest.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let number = Double(rest)
        else { return nil }
        return TokenCount(Int((number * multiplier).rounded()), bound: bound)
    }

    private enum Section: Hashable {
        case categories, mcpTools, memoryFiles, skills, agents

        init?(heading: Substring) {
            let heading = heading.lowercased()
            if heading.contains("category") {
                self = .categories
            } else if heading.contains("mcp") {
                self = .mcpTools
            } else if heading.contains("memory") {
                self = .memoryFiles
            } else if heading.contains("skill") {
                self = .skills
            } else if heading.contains("agent") {
                self = .agents
            } else {
                return nil
            }
        }
    }

    /// `228.4k / 1m (23%)`
    private static func parseTotals(_ text: String) -> (used: Int, window: Int, percentage: Double)? {
        let parts = text.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let windowAndPercent = parts[1].split(separator: "(", maxSplits: 1)
        guard let used = tokenCount(String(parts[0]))?.value,
            let window = tokenCount(String(windowAndPercent[0]))?.value
        else { return nil }
        let percentText = windowAndPercent.count > 1 ? windowAndPercent[1].prefix { $0.isNumber || $0 == "." } : ""
        let percentage = Double(percentText) ?? (window > 0 ? (Double(used) / Double(window) * 100).rounded() : 0)
        return (used, window, percentage)
    }

    /// `| MCP tools | 197.1k | 19.7% |`; a name holding a `|` keeps it.
    private static func category(from cells: [String], window: Int) -> Category? {
        guard cells.count >= 3 else { return nil }
        let name = cells[..<(cells.count - 2)].joined(separator: "|")
        let percent = Double(cells[cells.count - 1].filter { $0.isNumber || $0 == "." })
        guard
            let tokens = tokenCount(cells[cells.count - 2])?.value
                ?? percent.map({ Int(($0 / 100 * Double(window)).rounded()) })
        else { return nil }
        return Category(name: name, tokens: tokens, kind: kind(ofCategory: name))
    }

    private static func kind(ofCategory name: String) -> Category.Kind {
        let lowered = name.lowercased()
        if lowered == "free space" { return .free }
        if lowered.contains("(deferred)") { return .deferred }
        if lowered.contains("buffer") { return .buffer }
        return .used
    }
}

private extension String {
    /// The text after a bold `**Label:**`, without the markdown line break that may trail it.
    func value(afterLabel label: String) -> String? {
        let prefix = "**\(label):**"
        guard hasPrefix(prefix) else { return nil }
        return dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

    /// The cells of a markdown table row, trimmed.
    var tableCells: [String] {
        var cells = split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }

    /// A cell of the rule under a table's header, like `------` or `:--:`.
    var isTableRule: Bool {
        !isEmpty && allSatisfy { $0 == "-" || $0 == ":" }
    }
}

private extension Array where Element == String {
    /// The cells between the first and the last, rejoined in case the text held a `|`.
    var middle: String {
        count > 2 ? self[1..<(count - 1)].joined(separator: "|") : ""
    }
}
