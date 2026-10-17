import Foundation

/// The one way Native prints recurring values, so every feature says the same thing the same way.
/// Pure functions of their inputs (pass `now` for anything relative), safe from any thread.
public nonisolated enum DSFormat {
    // MARK: Time

    /// A compact age for lists: "now", "5m", "3h", "4d", "2mo", "1y".
    public static func compactAge(_ date: Date, now: Date) -> String {
        let minutes = Int(max(now.timeIntervalSince(date), 0) / 60)
        let hour = 60, day = 60 * 24
        switch minutes {
        case ..<1: return "now"
        case ..<hour: return "\(minutes)m"
        case ..<day: return "\(minutes / hour)h"
        case ..<(day * 30): return "\(minutes / day)d"
        case ..<(day * 365): return "\(minutes / (day * 30))mo"
        default: return "\(minutes / (day * 365))y"
        }
    }

    /// A time to come, as precise as useful: "3:05 PM", "tomorrow at 9:00 AM",
    /// "Mon, Oct 20 at 3:00 PM".
    public static func time(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return clock
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(clock)"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(clock)"
    }

    /// How far off a time is: "in 42 min", "in 2 hr 14 min", "in 3 days"; nil once it has passed.
    public static func countdown(to date: Date, now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        if seconds < 60 { return "in under a minute" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "in \(hours) hr" : "in \(hours) hr \(minutes % 60) min" }
        let days = hours / 24
        let dayText = days == 1 ? "1 day" : "\(days) days"
        return hours % 24 == 0 ? "in \(dayText)" : "in \(dayText) \(hours % 24) hr"
    }

    /// "3:05 PM, in 42 min"
    public static func timeAndCountdown(_ date: Date, now: Date) -> String {
        [time(date, now: now), countdown(to: date, now: now)].compactMap(\.self).joined(separator: ", ")
    }

    // MARK: Counts

    /// Token counts, compact with at most one decimal as Claude Code prints them: "103", "2k",
    /// "228.4k", "1M".
    public static func tokens(_ count: Int) -> String {
        if abs(count) < 1_000 { return "\(count)" }
        let thousands = (Double(count) / 100).rounded() / 10
        if abs(thousands) < 1_000 { return oneDecimal(thousands) + "k" }
        return oneDecimal((Double(count) / 100_000).rounded() / 10) + "M"
    }

    /// A whole percentage: "42%".
    public static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// A share of a total, with one decimal below 10% so small rows don't read as nothing:
    /// "0.4%", "<0.1%", "38%".
    public static func share(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "–" }
        let fraction = Double(part) / Double(total)
        if part > 0, fraction < 0.001 { return "<0.1%" }
        return fraction.formatted(.percent.precision(.fractionLength(fraction < 0.1 ? 1 : 0)))
    }

    /// Changed-line counts for diffs: "12", "1.2k", "12k"; past 99k Conductor's "✱✱".
    public static func lineCount(_ count: Int) -> String {
        if count > 99_000 { return "✱✱" }
        if count >= 10_000 { return "\(Int((Double(count) / 1000).rounded()))k" }
        if count > 999 { return oneDecimal((Double(count) / 100).rounded() / 10) + "k" }
        return "\(count)"
    }

    /// A diff stat: "+12 −3", omitting a side that is zero ("+12", "−3").
    public static func diffStat(added: Int, removed: Int) -> String {
        [added > 0 ? "+\(lineCount(added))" : nil, removed > 0 ? "\u{2212}\(lineCount(removed))" : nil]
            .compactMap(\.self)
            .joined(separator: " ")
    }

    // MARK: System

    /// Memory as Activity Monitor writes it: "745.7 MB", "1.42 GB".
    public static func memory(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .memory))
    }

    /// CPU as a percent of one core, as ps and Activity Monitor report it, so it can pass 100%.
    /// One decimal below 10%, so idle processes don't all read 0%: "0.4%", "12%", "225%".
    public static func cpu(_ percentOfCore: Double) -> String {
        (percentOfCore / 100).formatted(.percent.precision(.fractionLength(percentOfCore < 10 ? 1 : 0)))
    }

    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }
}
