/// Calendar sections for the chooser. An active season belongs to this month; past dates belong
/// to their next occurrence. Unresolvable dates and unfinished artwork never enter the months.
public struct CelebrationListing: Sendable {
    public struct Month: Identifiable, Sendable {
        public let id: CivilDate
        public let events: [CelebrationEvent]
    }

    public let months: [Month]
    public let pending: [CelebrationEvent]
    public let matchCount: Int

    public init(events: [CelebrationEvent], preferences: CelebrationPreferences, today: CivilDate, query: String = "") {
        var dated: [(event: CelebrationEvent, date: CivilDate)] = []
        var pending: [CelebrationEvent] = []
        for event in events.map(preferences.styled) where event.contribution.matches(query) {
            if event.canBeChosen(on: today),
                let occurrence = event.nextOccurrence(window: preferences.selection(for: event.id).window, from: today)
            {
                dated.append((event, max(today, occurrence.display.first)))
            } else {
                pending.append(event)
            }
        }
        dated.sort { ($0.date, $0.event.order) < ($1.date, $1.event.order) }
        let groups = Dictionary(grouping: dated) { item in
            // The first of an already valid civil date's month always exists.
            item.date.adding(days: 1 - item.date.day)
        }
        months = groups.keys.sorted().map { Month(id: $0, events: groups[$0, default: []].map(\.event)) }
        self.pending = pending
        matchCount = dated.count + pending.count
    }
}
