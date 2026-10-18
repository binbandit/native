import Foundation
import Testing

@testable import AppAppearance

/// Native's own catalogue as the app loads it, with every compiled icon present.
enum CelebrationFixtures {
    static let halloween = FirstPartyCelebrations.halloweenID
    static let muertos = FirstPartyCelebrations.diaDeMuertosID
    static let homeMarks: Set<String> = [
        FirstPartyCelebrations.HomeMark.halloween, FirstPartyCelebrations.HomeMark.diaDeMuertos,
    ]

    static func catalog(
        _ contributions: [CelebrationContribution] = FirstPartyCelebrations.all,
        assetExists: @escaping (String) -> Bool = { _ in true }
    ) -> CelebrationCatalog {
        var catalog = CelebrationCatalog()
        catalog.add(
            CelebrationContributions(contributions),
            from: CelebrationSource(
                pluginID: "celebrations", location: .builtIn, assetExists: assetExists, homeMarks: homeMarks))
        return catalog
    }

    static var events: [CelebrationEvent] { catalog().events }

    static func enabled(_ ids: CelebrationID...) -> CelebrationPreferences {
        var preferences = CelebrationPreferences()
        for id in ids { preferences.setEnabled(true, for: id) }
        return preferences
    }

    static func day(_ text: String) throws -> CivilDate {
        try #require(CivilDate(text))
    }

    static func instant(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    static func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    /// The active celebration on `day`, or nil for the base appearance.
    static func active(
        _ preferences: CelebrationPreferences, on day: String, events: [CelebrationEvent] = events,
        canApplyAppIcon: Bool = true
    ) throws -> CelebrationID? {
        CelebrationPolicy.resolve(
            events, preferences: preferences, on: try Self.day(day), canApplyAppIcon: canApplyAppIcon
        ).active?.eventID
    }

    /// A synthetic year-crossing celebration, shaped like Kwanzaa (26 December through 1 January).
    static let crossYear = CelebrationContribution(
        id: CelebrationID("test.cross-year"),
        title: "Cross-year fixture",
        calendar: CelebrationCalendar(rule: .fixed(start: MonthDay(literal: 12, 26), end: MonthDay(literal: 1, 1))),
        artwork: CelebrationArtwork(home: .mark(FirstPartyCelebrations.HomeMark.halloween))
    )

    static let leapDay = CelebrationContribution(
        id: CelebrationID("test.leap-day"),
        title: "Leap day fixture",
        calendar: CelebrationCalendar(rule: .fixed(start: MonthDay(literal: 2, 29), end: MonthDay(literal: 2, 29))),
        artwork: CelebrationArtwork(home: .mark(FirstPartyCelebrations.HomeMark.halloween))
    )
}
