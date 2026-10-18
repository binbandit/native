import Foundation

/// A provider's usage-limit windows as an agent's own status command prints them: each window's
/// used share and when it resets.
///
/// Two formats are read, both rendered by the adapters without a model call:
/// - Claude Code's `/usage`: `**5-hour limit** — **42%** · Resets Oct 17, 3:00 PM PDT`
/// - Codex's `/status`: `**codex 5h limit:** 88% left (resets 15:00 on Oct 18)`
public struct ProviderUsageReport: Hashable, Sendable {
    public struct Window: Hashable, Sendable, Identifiable {
        /// The window as the agent names it: "5-hour limit", "Weekly · all models", "5h limit".
        public var name: String
        /// Used share of the window, 0-1.
        public var utilization: Double
        public var resetsAt: Date?

        public var id: String { name }

        public init(name: String, utilization: Double, resetsAt: Date? = nil) {
            self.name = name
            self.utilization = utilization
            self.resetsAt = resetsAt
        }
    }

    public var windows: [Window]
    public var capturedAt: Date

    public init(windows: [Window], capturedAt: Date = .now) {
        self.windows = windows
        self.capturedAt = capturedAt
    }

    /// Returns nil when the text lists no limit windows. Reset times without a zone are read in
    /// `timeZone`, the agent's own (adapters run on the same machine).
    public static func parse(
        _ markdown: String, now: Date = .now, timeZone: TimeZone = .current
    ) -> ProviderUsageReport? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let windows = markdown.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            return usedLine(line, now: now, calendar: calendar) ?? leftLine(line, now: now, calendar: calendar)
        }
        return windows.isEmpty ? nil : ProviderUsageReport(windows: windows, capturedAt: now)
    }

    /// `**5-hour limit** — **42%** · Resets Oct 17, 3:00 PM PDT`
    private static func usedLine(_ line: String, now: Date, calendar: Calendar) -> Window? {
        let pattern = /^\*\*(.+?)\*\* — \*\*(\d+(?:\.\d+)?)%\*\*(?: · Resets (.+))?$/
        guard let match = line.wholeMatch(of: pattern), let percent = Double(match.2) else { return nil }
        let resetsAt = match.3.flatMap { claudeDate(String($0), now: now, calendar: calendar) }
        return Window(name: String(match.1), utilization: percent / 100, resetsAt: resetsAt)
    }

    /// `**codex 5h limit:** 88% left (resets 15:00 on Oct 18)`
    private static func leftLine(_ line: String, now: Date, calendar: Calendar) -> Window? {
        let pattern = /^\*\*(.+?):\*\* (\d+(?:\.\d+)?)% left(?: \(resets (\d{1,2}):(\d{2})(?: on ([^)]+))?\))?$/
        guard let match = line.wholeMatch(of: pattern), let left = Double(match.2) else { return nil }
        var resetsAt: Date?
        if let hour = match.3.flatMap({ Int($0) }), let minute = match.4.flatMap({ Int($0) }) {
            resetsAt = codexDate(
                hour: hour, minute: minute, day: match.5.map(String.init), now: now, calendar: calendar)
        }
        return Window(name: windowName(String(match.1)), utilization: (100 - left) / 100, resetsAt: resetsAt)
    }

    /// Codex prefixes each window with its limit's id ("codex 5h limit"); the window is the rest.
    private static func windowName(_ name: String) -> String {
        let words = name.split(separator: " ")
        guard words.count > 2, let label = words.dropFirst().first,
            label.first?.isNumber == true || label.lowercased() == "weekly"
        else { return name }
        return words.dropFirst().joined(separator: " ")
    }

    /// "Oct 17, 3:00 PM PDT"; the year is the one that puts it nearest after now.
    private static func claudeDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.defaultDate = now
        for format in ["MMM d, h:mm a zzz", "MMM d, h:mm a", "MMM d, yyyy, h:mm a zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return rollForward(date, now: now, calendar: calendar, unit: .year)
            }
        }
        return nil
    }

    /// Today at the time, or on "Oct 18" / "18 Oct" when given.
    private static func codexDate(hour: Int, minute: Int, day: String?, now: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        if let day {
            let parts = day.split(separator: " ")
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            guard parts.count == 2,
                let month = parts.lazy.compactMap({ months.firstIndex(of: String($0.prefix(3)).lowercased()) }).first,
                let number = parts.lazy.compactMap({ Int($0) }).first
            else { return nil }
            components.month = month + 1
            components.day = number
        }
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else { return nil }
        return day == nil ? date : rollForward(date, now: now, calendar: calendar, unit: .year)
    }

    /// Resets lie ahead; a date well in the past means the next year's.
    private static func rollForward(_ date: Date, now: Date, calendar: Calendar, unit: Calendar.Component) -> Date {
        guard date < now.addingTimeInterval(-86_400) else { return date }
        return calendar.date(byAdding: unit, value: 1, to: date) ?? date
    }
}
