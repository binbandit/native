import Testing

@testable import AppAppearance

struct CelebrationListingTests {
    typealias F = CelebrationFixtures

    @Test func existingCountryMetadataReachesTheCatalogue() {
        let australian = FirstPartyCelebrations.celebrations.filter { $0.publicHolidays.contains("AU") }
        #expect(
            Set(australian.map(\.id))
                == Set(
                    [
                        "native.australia-day", "native.christmas", "native.easter", "native.new-year",
                    ].map { CelebrationID($0) }))
    }

    @Test func monthsStartTodayAndPastOctoberClosesTheList() throws {
        let halloween = try #require(F.events.first { $0.id == F.halloween })
        let past = CelebrationContribution(
            id: CelebrationID("test.past-october"), title: "Earlier October",
            calendar: CelebrationCalendar(
                rule: .fixed(start: MonthDay(literal: 10, 10), end: MonthDay(literal: 10, 10))),
            iconSet: FirstPartyCelebrations.halloweenIcons.id)
        let events = F.catalog([halloween.contribution, past]).celebrations
        let listing = CelebrationListing(
            events: events, preferences: F.enabled(F.halloween), today: try F.day("2026-10-23"))
        #expect(listing.months.map(\.id) == [try F.day("2026-10-01"), try F.day("2027-10-01")])
        #expect(listing.months.first?.events.first?.id == F.halloween)
    }

    @Test func aliasSearchKeepsOnlyMatchingMonthsAndPendingStaysSeparate() throws {
        let events = F.events
        let listing = CelebrationListing(
            events: events, preferences: .init(), today: try F.day("2026-10-23"), query: "Deepavali")
        #expect(listing.matchCount == 1)
        #expect(listing.months.flatMap(\.events).count + listing.pending.count == 1)
        let missing = CelebrationListing(
            events: events, preferences: .init(), today: try F.day("2026-10-23"), query: "no-such-festival")
        #expect(missing.matchCount == 0)
        #expect(missing.months.isEmpty)
    }
}
