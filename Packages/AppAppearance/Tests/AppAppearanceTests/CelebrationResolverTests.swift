import Foundation
import Testing

@testable import AppAppearance

/// The date resolvers beyond fixed dates, checked against published dates.
struct CelebrationResolverTests {
    typealias F = CelebrationFixtures

    /// Western Easter and Orthodox Pascha, from the churches' published tables (Church of England;
    /// Greek Orthodox Archdiocese paschalion): they match in 2025 and 2028 and differ otherwise.
    @Test(arguments: [
        (2024, "2024-03-31", "2024-05-05"), (2025, "2025-04-20", "2025-04-20"), (2026, "2026-04-05", "2026-04-12"),
        (2027, "2027-03-28", "2027-05-02"), (2028, "2028-04-16", "2028-04-16"), (2029, "2029-04-01", "2029-04-08"),
        (2030, "2030-04-21", "2030-04-28"),
    ])
    func easterAndPascha(year: Int, western: String, orthodox: String) throws {
        #expect(CelebrationRule.easter(.western, in: year) == (try F.day(western)))
        #expect(CelebrationRule.easter(.orthodox, in: year) == (try F.day(orthodox)))
    }

    @Test func mardiGrasIsFortySevenDaysBeforeEaster() throws {
        let span = try #require(CivilDayRange(first: try F.day("2027-01-01"), last: try F.day("2027-12-31")))
        let ranges = try #require(CelebrationRule.easter(.western, offset: -47, length: 1).coreRanges(overlapping: span))
        #expect(ranges.map(\.first) == [try F.day("2027-02-09")])
    }

    @Test(arguments: [
        // US Thanksgiving, 4th Thursday of November; Canada's, 2nd Monday of October; Ada Lovelace
        // Day, 2nd Tuesday of October; the last Monday of May (US Memorial Day) for ordinal -1.
        (11, 5, 4, 2026, "2026-11-26"), (11, 5, 4, 2027, "2027-11-25"), (10, 2, 2, 2026, "2026-10-12"),
        (10, 2, 2, 2027, "2027-10-11"), (10, 3, 2, 2026, "2026-10-13"), (10, 3, 2, 2027, "2027-10-12"),
        (5, 2, -1, 2026, "2026-05-25"),
    ])
    func nthWeekdays(month: Int, weekday: Int, ordinal: Int, year: Int, expected: String) throws {
        #expect(CelebrationRule.nthWeekday(ordinal, weekday, of: month, in: year) == (try F.day(expected)))
    }

    @Test func fifthWeekdayOnlyWhenTheMonthHasOne() {
        // November 2026 has four Thursdays' worth past the 26th? It has no fifth Thursday.
        #expect(CelebrationRule.nthWeekday(5, 5, of: 11, in: 2026) == nil)
    }

    @Test func programmersDayIsDay256() throws {
        let rule = CelebrationRule.dayOfYear(day: 256, length: 1)
        let span = try #require(CivilDayRange(first: try F.day("2026-01-01"), last: try F.day("2028-12-31")))
        #expect(try #require(rule.coreRanges(overlapping: span)).map(\.first.description) == ["2026-09-13", "2027-09-13", "2028-09-12"])
    }

    @Test func tablesExpireAfterTheirLastYear() throws {
        let json = """
            {"kind": "table", "occurrences": [{"start": "2026-12-05", "end": "2026-12-12"}, {"start": "2027-12-25", "end": "2028-01-01"}]}
            """
        let calendar = try JSONDecoder().decode(CelebrationCalendar.self, from: Data(json.utf8))
        let event = try #require(
            F.catalog([CelebrationContribution(id: CelebrationID("test.table"), title: "Table", calendar: calendar)])
                .celebrations.first)
        #expect(event.nextOccurrence(window: nil, from: try F.day("2027-06-01"))?.core.last == (try F.day("2028-01-01")))
        #expect(event.dateStatus(on: try F.day("2027-06-01")) == .resolvable)
        #expect(event.dateStatus(on: try F.day("2028-06-01")) == .coverageEnded(lastYear: 2027))
        #expect(event.nextOccurrence(window: nil, from: try F.day("2028-06-01")) == nil)
        let data = try JSONEncoder().encode(calendar)
        #expect(try JSONDecoder().decode(CelebrationCalendar.self, from: data) == calendar)
    }

    @Test func ruleKindsRoundTrip() throws {
        for json in [
            #"{"kind": "nth-weekday", "month": 11, "weekday": "thursday", "ordinal": 4}"#,
            #"{"kind": "day-of-year", "day": 256}"#, #"{"kind": "western-easter", "offset": -47}"#,
            #"{"kind": "orthodox-pascha"}"#,
        ] {
            let calendar = try JSONDecoder().decode(CelebrationCalendar.self, from: Data(json.utf8))
            #expect(calendar.rule.isResolvable)
            #expect(try JSONDecoder().decode(CelebrationCalendar.self, from: JSONEncoder().encode(calendar)) == calendar)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CelebrationCalendar.self, from: Data(#"{"kind": "nth-weekday", "month": 1, "weekday": "funday", "ordinal": 1}"#.utf8))
        }
    }
}
