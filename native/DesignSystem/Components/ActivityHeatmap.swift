import SwiftUI

/// A year of activity as GitHub draws it: one square per day, a column per week, colored in five
/// steps of the accent by how much happened. Hovering shows a day; a click or tap picks one (again
/// to let go), and with focus the arrow keys move the pick a day or a week. The caller shows the
/// day's numbers, and every square tells VoiceOver and its tooltip exactly what happened that day.
public struct ActivityHeatmap: View {
    let values: [Date: Double]
    let estimated: Set<Date>
    let end: Date
    @Binding var selection: Date?
    @Binding var hovered: Date?
    let describe: (Date) -> String

    @Environment(\.calendar) private var calendar
    @State private var width: CGFloat = 0

    /// - Parameters:
    ///   - values: Each day's amount, keyed by the day's start in the environment's calendar.
    ///   - estimated: Days whose amount is an estimate; their squares say so.
    ///   - end: The last day shown, usually today.
    ///   - describe: A day in words, for its tooltip and VoiceOver: "12 prompts on Tuesday, March 4".
    public init(
        values: [Date: Double], estimated: Set<Date> = [], endingOn end: Date = .now, selection: Binding<Date?>,
        hovered: Binding<Date?>, describe: @escaping (Date) -> String
    ) {
        self.values = values
        self.estimated = estimated
        self.end = end
        _selection = selection
        _hovered = hovered
        self.describe = describe
    }

    private static let weeks = 53
    private static let gap: CGFloat = 3
    private static let ringInset: CGFloat = 2.5
    private static let labelWidth: CGFloat = 28
    private static let monthHeight: CGFloat = 16

    /// Fills the width, between a size still worth tapping and GitHub's largest.
    private var cell: CGFloat {
        let available = width - Self.labelWidth - Self.gap * CGFloat(Self.weeks - 1)
        return min(max(available / CGFloat(Self.weeks), 7), 14)
    }

    public var body: some View {
        let layout = Layout(end: end, calendar: calendar, weeks: Self.weeks)
        let levels = Levels(values: Array(values.values))
        VStack(alignment: .leading, spacing: 0) {
            monthLabels(layout)
            HStack(alignment: .top, spacing: 0) {
                weekdayLabels(layout)
                grid(layout, levels: levels)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private func grid(_ layout: Layout, levels: Levels) -> some View {
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(0..<Self.weeks, id: \.self) { week in
                VStack(spacing: Self.gap) {
                    ForEach(0..<7, id: \.self) { weekday in
                        square(layout.day(week: week, weekday: weekday), levels: levels)
                    }
                }
            }
        }
        .contentShape(.rect)
        .onContinuousHover { phase in
            if case .active(let point) = phase {
                hovered = layout.day(at: point, cell: cell, gap: Self.gap)
            } else {
                hovered = nil
            }
        }
        // A tap rather than a drag, so a swipe across the graph still scrolls the page on touch.
        .onTapGesture(coordinateSpace: .local) { point in
            if let day = layout.day(at: point, cell: cell, gap: Self.gap) {
                selection = day == selection ? nil : day
            }
        }
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let days =
                switch press.key {
                case .leftArrow: -7
                case .rightArrow: 7
                case .upArrow: -1
                default: 1
                }
            selection = layout.clamped(
                selection.flatMap { calendar.date(byAdding: .day, value: days, to: $0) } ?? layout.end)
            return .handled
        }
        .onKeyPress(.escape) {
            guard selection != nil else { return .ignored }
            selection = nil
            return .handled
        }
    }

    @ViewBuilder
    private func square(_ day: Date?, levels: Levels) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        if let day {
            let level = levels.level(of: values[day] ?? 0)
            let isPicked = day == selection || day == hovered
            ZStack {
                if level == 0 {
                    shape.fill(.dsSelected)
                } else {
                    shape.fill(.dsAccentSubtle)
                    shape.fill(.dsAccent.opacity(Levels.opacity(level)))
                }
            }
            .frame(width: cell, height: cell)
            .overlay {
                // Around the square, in the gap, so it shows on the strongest step too.
                if isPicked {
                    RoundedRectangle(cornerRadius: DS.Radius.small + Self.ringInset, style: .continuous)
                        .strokeBorder(day == selection ? Color.dsTextPrimary : .dsTextSecondary, lineWidth: 1.5)
                        .padding(-Self.ringInset)
                }
            }
            .help(describe(day) + (estimated.contains(day) ? " (estimated from the agents’ session lists)" : ""))
            .accessibilityElement()
            .accessibilityLabel(describe(day))
            .accessibilityHint(estimated.contains(day) ? "Estimated" : "")
            .accessibilityAddTraits(day == selection ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection = day }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func monthLabels(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.monthStarts, id: \.week) { start in
                Text(start.title)
                    .font(.dsMicro)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize()
                    .offset(x: Self.labelWidth + CGFloat(start.week) * (cell + Self.gap))
            }
        }
        .frame(height: Self.monthHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func weekdayLabels(_ layout: Layout) -> some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(0..<7, id: \.self) { row in
                // Every other row, as GitHub labels Mon, Wed and Fri.
                Text(row % 2 == 1 ? layout.weekdaySymbol(row: row) : "")
                    .font(.dsMicro)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: Self.labelWidth, height: cell, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

extension ActivityHeatmap {
    /// Which day each square is: columns are weeks starting on the calendar's first weekday, the
    /// last column holding `end`.
    struct Layout {
        let start: Date
        let end: Date
        let calendar: Calendar
        let weeks: Int

        init(end: Date, calendar: Calendar, weeks: Int) {
            let last = calendar.startOfDay(for: end)
            let weekday = calendar.component(.weekday, from: last)
            let intoWeek = (weekday - calendar.firstWeekday + 7) % 7
            let lastWeekStart = calendar.date(byAdding: .day, value: -intoWeek, to: last) ?? last
            start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: lastWeekStart) ?? lastWeekStart
            self.end = last
            self.calendar = calendar
            self.weeks = weeks
        }

        func day(week: Int, weekday: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start), day <= end else {
                return nil
            }
            return day
        }

        /// The day, kept within the graph.
        func clamped(_ day: Date) -> Date {
            min(max(day, start), end)
        }

        func day(at point: CGPoint, cell: CGFloat, gap: CGFloat) -> Date? {
            guard point.x >= 0, point.y >= 0 else { return nil }
            let week = Int(point.x / (cell + gap)), weekday = Int(point.y / (cell + gap))
            guard week < weeks, weekday < 7 else { return nil }
            return day(week: week, weekday: weekday)
        }

        func weekdaySymbol(row: Int) -> String {
            let symbols = calendar.shortWeekdaySymbols
            return symbols[(calendar.firstWeekday - 1 + row) % 7]
        }

        /// The weeks where a month begins, for the labels above the grid; the first only if it has
        /// room for its name before the next.
        var monthStarts: [(week: Int, title: String)] {
            var starts: [(week: Int, title: String)] = []
            var previous: Int?
            for week in 0..<weeks {
                guard let day = day(week: week, weekday: 0) ?? day(week: week, weekday: 6) else { continue }
                let month = calendar.component(.month, from: day)
                if month != previous {
                    starts.append((week, calendar.shortMonthSymbols[month - 1]))
                    previous = month
                }
            }
            if starts.count > 1, starts[1].week - starts[0].week < 3 {
                starts.removeFirst()
            }
            return starts
        }
    }

    /// Five steps by quintile of the days with any activity, so one huge day doesn't wash out the
    /// rest.
    struct Levels {
        let thresholds: [Double]

        init(values: [Double]) {
            let active = values.filter { $0 > 0 }.sorted()
            thresholds = active.isEmpty ? [] : (1...4).map { active[min(active.count - 1, active.count * $0 / 5)] }
        }

        func level(of value: Double) -> Int {
            guard value > 0 else { return 0 }
            return 1 + thresholds.count { value > $0 }
        }

        static func opacity(_ level: Int) -> Double {
            [0, 0.2, 0.4, 0.6, 0.8, 1][min(max(level, 0), 5)]
        }
    }
}
