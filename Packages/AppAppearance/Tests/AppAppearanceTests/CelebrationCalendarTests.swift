import Foundation
import Testing

@testable import AppAppearance

/// Civil-day arithmetic, occurrences and boundaries, across years, leap days, daylight saving and
/// time zones.
struct CelebrationCalendarTests {
    typealias F = CelebrationFixtures

    @Test func dayNumbersRoundTrip() throws {
        for text in ["1970-01-01", "2000-02-29", "2026-10-31", "2027-03-14", "1899-12-31", "2400-02-29"] {
            let day = try F.day(text)
            #expect(CivilDate(dayNumber: day.dayNumber) == day)
            #expect(day.adding(days: 1).adding(days: -1) == day)
        }
        #expect(try F.day("1970-01-01").dayNumber == 0)
        #expect(try F.day("2026-12-31").adding(days: 1) == (try F.day("2027-01-01")))
        #expect(try F.day("2028-02-28").adding(days: 1) == (try F.day("2028-02-29")))
        #expect(try F.day("2027-02-28").adding(days: 1) == (try F.day("2027-03-01")))
        #expect(CivilDate("2027-02-29") == nil)
        #expect(MonthDay("02-30") == nil)
        #expect(MonthDay("02-29") != nil)
    }

    @Test(arguments: [
        ("2026-09-30", false), ("2026-10-01", true), ("2026-10-31", true), ("2026-11-07", true),
        ("2026-11-08", false), ("2027-10-01", true), ("2028-02-29", false),
    ])
    func halloweenWindow(day: String, isShown: Bool) throws {
        #expect((try F.active(F.enabled(F.halloween), on: day) == F.halloween) == isShown)
    }

    @Test func halloweenCoreIsTheThirtyFirst() throws {
        let event = try #require(F.catalog().celebration(F.halloween))
        let occurrence = try #require(event.nextOccurrence(window: nil, from: try F.day("2026-10-18")))
        #expect(occurrence.core == CivilDayRange(day: try F.day("2026-10-31")))
        #expect(occurrence.display.first == (try F.day("2026-10-01")))
        #expect(occurrence.display.last == (try F.day("2026-11-07")))
        #expect(occurrence.display.dayCount == 38)
        #expect(occurrence.tier(on: try F.day("2026-10-31")) == .core)
        #expect(occurrence.tier(on: try F.day("2026-11-01")) == .decorative)
        #expect(occurrence.id.description == "native.halloween@2026-10-31")
    }

    @Test func muertosCoreAndExtendedWindows() throws {
        let event = try #require(F.catalog().celebration(F.muertos))
        let core = try #require(event.nextOccurrence(window: nil, from: try F.day("2026-10-18")))
        #expect(core.display == CivilDayRange(first: try F.day("2026-11-01"), last: try F.day("2026-11-02")))
        let extended = try #require(
            event.nextOccurrence(window: FirstPartyCelebrations.extended, from: try F.day("2026-10-18")))
        #expect(extended.display == CivilDayRange(first: try F.day("2026-10-28"), last: try F.day("2026-11-03")))
        #expect(extended.core == core.core)
    }

    @Test func windowCrossingTheYear() throws {
        let event = try #require(F.catalog([F.crossYear]).celebrations.first)
        let newYear = try #require(CivilDayRange(first: try F.day("2026-12-30"), last: try F.day("2027-01-02")))
        let occurrences = event.occurrences(window: nil, overlapping: newYear)
        #expect(occurrences.map(\.id.description) == ["test.cross-year@2026-12-26"])
        #expect(occurrences.first?.core.last == (try F.day("2027-01-01")))

        // Two occurrences touch one Gregorian year: the one ending on New Year's Day, and the next.
        let year = try #require(CivilDayRange(first: try F.day("2027-01-01"), last: try F.day("2027-12-31")))
        #expect(
            event.occurrences(window: nil, overlapping: year).map(\.id.description) == [
                "test.cross-year@2026-12-26", "test.cross-year@2027-12-26",
            ])

        let preferences = F.enabled(event.id)
        let events = [event]
        #expect(try F.active(preferences, on: "2026-12-26", events: events) == event.id)
        #expect(try F.active(preferences, on: "2027-01-01", events: events) == event.id)
        #expect(try F.active(preferences, on: "2027-01-02", events: events) == nil)
        let resolution = CelebrationPolicy.resolve(events, preferences: preferences, on: try F.day("2026-12-31"))
        #expect(resolution.nextChange == (try F.day("2027-01-02")))
    }

    @Test func leapDayOnlyInLeapYears() throws {
        let event = try #require(F.catalog([F.leapDay]).celebrations.first)
        let decade = try #require(CivilDayRange(first: try F.day("2026-01-01"), last: try F.day("2033-12-31")))
        #expect(event.occurrences(window: nil, overlapping: decade).map(\.core.first.year) == [2028, 2032])
        #expect(event.nextOccurrence(window: nil, from: try F.day("2028-03-01")) == nil)
    }

    @Test func localDatesFollowTheTimeZone() throws {
        let opening = try F.instant("2026-09-30T14:00:00Z")
        #expect(CivilDate(opening, in: try F.zone("Australia/Melbourne")) == (try F.day("2026-10-01")))
        #expect(CivilDate(opening, in: try F.zone("America/Los_Angeles")) == (try F.day("2026-09-30")))
    }

    @Test func boundariesAreLocalMidnightsAcrossDaylightSaving() throws {
        let melbourne = try F.zone("Australia/Melbourne")
        // Melbourne moves to daylight time on 4 October, inside the window; the base still returns at
        // midnight local time on 8 November.
        let opening = CivilDate(try F.instant("2026-10-01T00:00:00Z"), in: melbourne)
        let schedule = CelebrationPolicy.schedule(
            F.events, preferences: F.enabled(F.halloween), from: opening, through: try F.day("2026-11-30"))
        #expect(schedule.map(\.occurrence?.eventID) == [F.halloween, nil])
        let close = try #require(schedule.last?.days.first)
        #expect(close == (try F.day("2026-11-08")))
        #expect(close.start(in: melbourne) == (try F.instant("2026-11-07T13:00:00Z")))
        #expect(opening.start(in: melbourne) == (try F.instant("2026-09-30T14:00:00Z")))
        // The window is 38 calendar days though one of them is only 23 hours long.
        #expect(schedule.first?.days.dayCount == 38)
    }

    @Test func dayStartWhenDaylightSavingSkipsMidnight() throws {
        // Cuba springs forward at midnight on 14 March 2027, so that day begins at 01:00.
        let havana = try F.zone("America/Havana")
        let start = try F.day("2027-03-14").start(in: havana)
        #expect(start == (try F.instant("2027-03-14T05:00:00Z")))
        #expect(CivilDate(start, in: havana) == (try F.day("2027-03-14")))
        #expect(CivilDate(start.addingTimeInterval(-1), in: havana) == (try F.day("2027-03-13")))
    }

    @Test func travellingChangesTheDay() throws {
        // The same instant is 1 November in Melbourne (Día de Muertos) and 31 October in Los Angeles.
        let instant = try F.instant("2026-10-31T20:00:00Z")
        let preferences = F.enabled(F.halloween, F.muertos)
        let inMelbourne = CelebrationPolicy.resolve(
            F.events, preferences: preferences, on: CivilDate(instant, in: try F.zone("Australia/Melbourne")))
        let inLosAngeles = CelebrationPolicy.resolve(
            F.events, preferences: preferences, on: CivilDate(instant, in: try F.zone("America/Los_Angeles")))
        #expect(inMelbourne.active?.eventID == F.muertos)
        #expect(inLosAngeles.active?.eventID == F.halloween)
    }

    @Test func manualClockChangesRecompute() throws {
        let preferences = F.enabled(F.halloween, F.muertos)
        let before = CelebrationPolicy.resolve(F.events, preferences: preferences, on: try F.day("2026-10-15"))
        // Halloween's own day is the next change: its tier, and so the chooser's reason, changes then.
        #expect(before.nextChange == (try F.day("2026-10-31")))
        // The clock is set forward past the season, then back into it: each answer depends only on
        // the new day, and the next boundary is always after it.
        let forward = CelebrationPolicy.resolve(F.events, preferences: preferences, on: try F.day("2026-11-09"))
        #expect(forward.active == nil)
        #expect(forward.nextChange == (try F.day("2027-10-01")))
        let back = CelebrationPolicy.resolve(F.events, preferences: preferences, on: try F.day("2026-09-20"))
        #expect(back.active == nil)
        #expect(back.nextChange == (try F.day("2026-10-01")))
    }

    @Test func unsupportedCalendarsAndExpiredTablesKeepTheBase() throws {
        let easter = CelebrationContribution(
            id: CelebrationID("test.easter"), title: "Easter",
            calendar: CelebrationCalendar(rule: .unsupported(kind: "western-easter")),
            iconSet: FirstPartyCelebrations.halloweenIcons.id)
        var table = F.crossYear
        table.id = CelebrationID("test.table")
        table.provenance.coverage = .init(from: 2026, through: 2026)
        let catalog = F.catalog([easter, table])
        let events = catalog.celebrations
        let preferences = F.enabled(easter.id, table.id)
        #expect(
            catalog.celebration(easter.id)?.dateStatus(on: try F.day("2027-04-01"))
                == .unsupportedCalendar("western-easter"))
        #expect(try F.active(preferences, on: "2027-01-01", events: events) == table.id)
        #expect(try F.active(preferences, on: "2027-12-26", events: events) == nil)
        #expect(
            catalog.celebration(table.id)?.dateStatus(on: try F.day("2027-12-26")) == .coverageEnded(lastYear: 2026))
        #expect(
            CelebrationPolicy.resolve(events, preferences: preferences, on: try F.day("2027-12-26")).nextChange == nil)
    }
}
