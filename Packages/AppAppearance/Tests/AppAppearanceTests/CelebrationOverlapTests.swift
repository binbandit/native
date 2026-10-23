import Testing

@testable import AppAppearance

struct CelebrationOverlapTests {
    typealias F = CelebrationFixtures

    @Test func coreDatesNeedNoChoice() throws {
        let result = CelebrationPolicy.overlaps(
            F.events, preferences: F.enabled(F.halloween, F.muertos),
            from: try F.day("2026-10-23"), days: 365)
        #expect(result.isEmpty)
    }

    @Test func yearCrossingCollisionAndPreference() throws {
        let kwanzaa = CelebrationID("native.kwanzaa")
        let newYear = CelebrationID("native.new-year")
        // Use the real catalogue's dates with ready artwork on both surfaces.
        let events = F.events.map { event in
            CelebrationEvent(
                contribution: event.contribution, pluginID: event.pluginID,
                order: event.order, iconSet: F.events.first { $0.id == F.halloween }?.iconSet)
        }
        var preferences = F.enabled(kwanzaa, F.halloween, newYear)
        let result = CelebrationPolicy.overlaps(
            events, preferences: preferences,
            from: try F.day("2026-10-23"), days: 365)
        let overlap = try #require(result.first)
        #expect(result.count == 1)
        #expect(Set([overlap.first, overlap.second]) == [kwanzaa, newYear])
        #expect(overlap.days.first == (try F.day("2026-12-31")))
        #expect(overlap.days.last == (try F.day("2027-01-01")))
        #expect(overlap.tier == .core)
        preferences.prefer(newYear, over: kwanzaa, in: events)
        #expect(preferences.order(in: events) == [newYear, kwanzaa, F.halloween])
        #expect(
            CelebrationPolicy.resolve(
                events, preferences: preferences,
                on: try F.day("2026-12-31")
            ).active?.eventID == newYear)
        preferences.skipped.insert(.init(eventID: newYear, coreStart: try F.day("2026-12-31")))
        #expect(
            CelebrationPolicy.overlaps(
                events, preferences: preferences,
                from: try F.day("2026-10-23"), days: 365
            ).isEmpty)
    }

    @Test func decorativeTiesAreSplitAroundCoreDatesAndClipped() throws {
        var preferences = F.enabled(F.halloween, F.muertos)
        preferences.selections[F.muertos]?.window = FirstPartyCelebrations.extended
        let result = CelebrationPolicy.overlaps(
            F.events, preferences: preferences,
            from: try F.day("2026-10-30"), days: 5)
        #expect(result.map(\.days.first) == [try F.day("2026-10-30"), try F.day("2026-11-03")])
        #expect(result.allSatisfy { $0.tier == .decorative })
        #expect(result.last?.days.last == (try F.day("2026-11-03")))
        #expect(
            CelebrationPolicy.overlaps(
                F.events, preferences: preferences,
                from: try F.day("2026-10-30"), days: 0
            ).isEmpty)
    }
    @Test func fullCatalogueOffersOnlyActualPriorityTies() throws {
        let events = F.events.map { event in
            CelebrationEvent(
                contribution: event.contribution, pluginID: event.pluginID,
                order: event.order, iconSet: F.events.first { $0.id == F.halloween }?.iconSet)
        }
        var preferences = CelebrationPreferences()
        for event in events { preferences.setEnabled(true, for: event.id) }
        let overlaps = CelebrationPolicy.overlaps(
            events, preferences: preferences,
            from: try F.day("2026-10-23"), days: 365)
        #expect(!overlaps.isEmpty)
        for overlap in overlaps {
            let result = CelebrationPolicy.resolve(events, preferences: preferences, on: overlap.days.first)
            guard let active = result.active else { Issue.record("An overlap must have a winner"); continue }
            if case .priority = active.reason {} else { Issue.record("Only priority ties need a choice") }
        }
    }

}
