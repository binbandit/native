import Foundation

/// A usage limit that stopped a turn, recognized from how the agent failed it.
///
/// Neither adapter reports the limit itself in a structured way when a turn is refused:
/// - Claude Code fails `session/prompt` with an internal error whose message carries Claude Code's
///   text ("You've hit your session limit · resets 3pm (America/Los_Angeles)"), and sends the same
///   text as an agent message. Its `_meta` rate-limit status only arrives when the turn got as far
///   as a model response.
/// - Codex fails it with an internal error whose `data` has `codexErrorInfo: "usageLimitExceeded"`
///   and the text in `data.message` ("You've hit your usage limit. … Try again at 3:05 PM."), which
///   it also sends as an agent message. Its own rate-limit snapshots stay inside the adapter.
public struct UsageLimitHit: Hashable, Sendable {
    /// The provider's message, as the user would read it.
    public var message: String
    /// When the limit resets, if the message says.
    public var resetsAt: Date?
    /// Which limit, if the message names one Claude Code uses.
    public var window: RateLimitInfo.Window?

    public init(message: String, resetsAt: Date? = nil, window: RateLimitInfo.Window? = nil) {
        self.message = message
        self.resetsAt = resetsAt
        self.window = window
    }

    /// Recognizes a limit from a failed turn's error, or failing that, from the agent's last message
    /// in the turn. Reset times without a zone are read in `timeZone`, the agent's own (both adapters
    /// run on this Mac).
    public init?(error: any Error, agentText: String? = nil, now: Date = .now, timeZone: TimeZone = .current) {
        var texts: [String] = []
        var isFlagged = false
        if let error = error as? RPCError {
            let data = error.data
            if data?["codexErrorInfo"]?.stringValue == "usageLimitExceeded" {
                isFlagged = true
            }
            texts += [data?["message"]?.stringValue, data?["additionalDetails"]?.stringValue].compactMap(\.self)
            texts.append(Self.strippingErrorPrefix(error.message))
        } else {
            texts.append(error.localizedDescription)
        }
        if let agentText {
            texts.append(agentText)
        }
        let candidates = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let message = candidates.first(where: Self.isLimitMessage) ?? (isFlagged ? candidates.first : nil) else {
            return nil
        }
        self.init(
            message: message,
            resetsAt: candidates.lazy.compactMap { Self.resetDate(in: $0, now: now, timeZone: timeZone) }.first,
            window: Self.window(in: message)
        )
    }

    /// Recognizes a limit from text alone, such as an agent message.
    public init?(text: String, now: Date = .now, timeZone: TimeZone = .current) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isLimitMessage(text) else { return nil }
        self.init(
            message: text, resetsAt: Self.resetDate(in: text, now: now, timeZone: timeZone),
            window: Self.window(in: text))
    }

    /// Whether `text` is a provider's "usage limit reached" message: one of the Agent SDK's
    /// `USAGE_LIMIT_ERROR_PREFIXES`, or Codex's equivalents.
    public static func isLimitMessage(_ text: String) -> Bool {
        let text = normalized(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return limitPrefixes.contains { text.hasPrefix($0) }
    }

    private static let limitPrefixes = [
        // Claude Code (`USAGE_LIMIT_ERROR_PREFIXES` in the Agent SDK).
        "You've hit your",
        "You've reached your",
        "You're out of usage credits",
        "Your org is out of usage",
        "Your seat type doesn't include usage",
        "Your usage allocation has been disabled by your admin",
        "Your group's usage limit is set to $0",
        "Fable 5 requires usage credits",
        "You're out of extra usage",
        "Your seat type doesn't include extra usage",
        // Codex (`UsageLimitReachedError` in codex-rs), when its error code doesn't come through.
        "You hit your spend cap",
        "Your workspace is out of credits",
    ]

    /// Folds the typographic apostrophes and spaces agents print into plain ones.
    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// "Internal error: You've hit…" → "You've hit…"
    private static func strippingErrorPrefix(_ message: String) -> String {
        let prefix = "Internal error: "
        return message.hasPrefix(prefix) ? String(message.dropFirst(prefix.count)) : message
    }

    private static func window(in text: String) -> RateLimitInfo.Window? {
        let text = normalized(text)
        let names: [(String, RateLimitInfo.Window)] = [
            ("your session limit", .fiveHour),
            ("your weekly limit", .sevenDay),
            ("your Opus limit", .sevenDayOpus),
            ("your Sonnet limit", .sevenDaySonnet),
        ]
        return names.first { text.contains($0.0) }?.1
    }

    // MARK: Reset times

    /// Reads when a limit resets from a provider's message:
    /// - Claude Code: "resets 3pm (America/Los_Angeles)", "resets 3:30pm", "resets Oct 20, 3pm",
    ///   "resets Oct 20, 2027, 3pm", "resets in 2h 30m".
    /// - Codex: "Try again at 3:05 PM.", "try again at Oct 18th, 2026 3:05 PM."
    /// A time without a date is the next one to come.
    public static func resetDate(in text: String, now: Date = .now, timeZone: TimeZone = .current) -> Date? {
        let text = normalized(text)
        for keyword in ["resets ", "try again at ", "Try again at "] {
            guard let range = text.range(of: keyword, options: .backwards) else { continue }
            var phrase = Substring(text[range.upperBound...])
            // The phrase runs to the next " · " separator, or the end of the sentence.
            if let separator = phrase.range(of: " ·") { phrase = phrase[..<separator.lowerBound] }
            if let newline = phrase.firstIndex(where: \.isNewline) { phrase = phrase[..<newline] }
            var zone = timeZone
            if let open = phrase.lastIndex(of: "("), let close = phrase.lastIndex(of: ")"), open < close {
                if let named = TimeZone(identifier: String(phrase[phrase.index(after: open)..<close])) {
                    zone = named
                }
                phrase = phrase[..<open]
            }
            let cleaned = phrase.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".,")))
            if let date = relativeDate(cleaned, now: now) ?? absoluteDate(cleaned, now: now, timeZone: zone) {
                return date
            }
        }
        return nil
    }

    /// "in 2h 30m", "in 5 hours"
    private static func relativeDate(_ phrase: String, now: Date) -> Date? {
        guard phrase.lowercased().hasPrefix("in ") else { return nil }
        var seconds = 0.0
        var number = ""
        var matched = false
        for character in phrase.dropFirst(3).lowercased() + " " {
            if character.isNumber || character == "." {
                number.append(character)
            } else if let value = Double(number),
                let unit = ["d": 86_400.0, "h": 3_600, "m": 60, "s": 1][String(character)]
            {
                seconds += value * unit
                number = ""
                matched = true
            } else if !character.isLetter {
                continue
            } else if !number.isEmpty {
                return nil
            }
        }
        return matched ? now.addingTimeInterval(seconds) : nil
    }

    /// "3pm", "3:05 PM", "15:00", "Oct 20, 3pm", "Oct 18th, 2026 3:05 PM"
    private static func absoluteDate(_ phrase: String, now: Date, timeZone: TimeZone) -> Date? {
        var tokens =
            phrase
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map { $0.lowercased() }
            .filter { $0 != "at" }
        guard !tokens.isEmpty else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        var hasDate = false
        var hasYear = false

        if let month = month(named: tokens[0]) {
            guard tokens.count >= 3, let day = Int(tokens[1].prefix { $0.isNumber }), (1...31).contains(day) else {
                return nil
            }
            components.month = month
            components.day = day
            hasDate = true
            tokens.removeFirst(2)
            if let year = Int(tokens[0]), tokens[0].count == 4 {
                components.year = year
                hasYear = true
                tokens.removeFirst()
            }
        }

        // What's left is the time: "3pm", "3:05pm", "3:05 pm", or a 24-hour "15:00".
        let time = tokens.joined()
        let meridiem: Character? = time.hasSuffix("am") ? "a" : time.hasSuffix("pm") ? "p" : nil
        let clock = meridiem == nil ? Substring(time) : time.dropLast(2)
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0..<60).contains(minute) else { return nil }
        switch meridiem {
        case "a"?:
            guard (1...12).contains(hour) else { return nil }
            components.hour = hour % 12
        case "p"?:
            guard (1...12).contains(hour) else { return nil }
            components.hour = hour % 12 + 12
        default:
            guard parts.count == 2, (0..<24).contains(hour) else { return nil }
            components.hour = hour
        }
        components.minute = minute
        components.second = 0

        guard var date = calendar.date(from: components) else { return nil }
        // Resets are in the future, give or take the minute the message rounded away.
        if !hasDate, date < now.addingTimeInterval(-60) {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } else if hasDate, !hasYear, date < now.addingTimeInterval(-86_400) {
            date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
        return date
    }

    private static func month(named token: String) -> Int? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard token.count >= 3, token.allSatisfy(\.isLetter) else { return nil }
        return months.firstIndex(of: String(token.prefix(3))).map { $0 + 1 }
    }
}
