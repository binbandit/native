import Foundation
import Testing

@testable import AppAppearance

struct SeasonalAppIconsTests {
    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    @Test(arguments: [
        ("2026-09-30T23:59:59Z", false),
        ("2026-10-01T00:00:00Z", true),
        ("2026-10-31T23:59:59Z", true),
        ("2026-11-07T23:59:59Z", true),
        ("2026-11-08T00:00:00Z", false),
        ("2027-10-01T00:00:00Z", true),
        ("2028-02-29T12:00:00Z", false),
    ])
    func availability(value: String, expected: Bool) throws {
        #expect(SeasonalAppIcons.halloweenIsAvailable(on: try date(value), timeZone: .gmt) == expected)
    }

    @Test func boundariesUseLocalDates() throws {
        let melbourne = try #require(TimeZone(identifier: "Australia/Melbourne"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let opening = try date("2026-09-30T14:00:00Z")
        #expect(SeasonalAppIcons.halloweenIsAvailable(on: opening, timeZone: melbourne))
        #expect(!SeasonalAppIcons.halloweenIsAvailable(on: opening, timeZone: losAngeles))
        let closing = try date("2026-11-07T13:00:00Z")
        #expect(!SeasonalAppIcons.halloweenIsAvailable(on: closing, timeZone: melbourne))
        #expect(SeasonalAppIcons.halloweenIsAvailable(on: closing.addingTimeInterval(-1), timeZone: melbourne))
    }

    @Test func schedulesClosingAcrossDaylightSaving() throws {
        let melbourne = try #require(TimeZone(identifier: "Australia/Melbourne"))
        #expect(SeasonalAppIcons.nextHalloweenBoundary(after: try date("2026-10-01T00:00:00Z"), timeZone: melbourne)
            == (try date("2026-11-07T13:00:00Z")))
    }

    @Test func schedulesNextOpeningAfterClosing() throws {
        #expect(SeasonalAppIcons.nextHalloweenBoundary(after: try date("2026-11-08T00:00:00Z"), timeZone: .gmt)
            == (try date("2027-10-01T00:00:00Z")))
    }
}
