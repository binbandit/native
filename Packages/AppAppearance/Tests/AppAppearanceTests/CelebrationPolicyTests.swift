import Foundation
import Testing

@testable import AppAppearance

/// The overlap policy: choice or skip, then core dates, then the user's order, then the base.
struct CelebrationPolicyTests {
    typealias F = CelebrationFixtures

    /// The spec's example: Halloween through 31 October, Día de Muertos on 1–2 November, Halloween
    /// again on 3–7 November, and the base on 8 November.
    @Test func halloweenAndMuertosOverlap() throws {
        let both = F.enabled(F.halloween, F.muertos)
        let schedule = CelebrationPolicy.schedule(
            F.events, preferences: both, from: try F.day("2026-10-15"), through: try F.day("2026-11-10"))
        #expect(
            schedule.map { "\($0.days.first)…\($0.days.last) \($0.occurrence?.eventID.rawValue ?? "base")" } == [
                "2026-10-15…2026-10-31 native.halloween",
                "2026-11-01…2026-11-02 native.dia-de-muertos",
                "2026-11-03…2026-11-07 native.halloween",
                "2026-11-08…2026-11-10 base",
            ])
        let first = CelebrationPolicy.resolve(F.events, preferences: both, on: try F.day("2026-11-01"))
        #expect(first.active?.reason == .coreDates(over: F.halloween))
        #expect(first.runnersUp.map(\.eventID) == [F.halloween])
        // Día de Muertos has no icon yet, so on its days the icon is the base, not Halloween's: one
        // resolved celebration drives both surfaces.
        #expect(first.active?.appliesToAppIcon == false)
        #expect(first.active?.appliesToHome == true)
        #expect(first.nextChange == (try F.day("2026-11-03")))
        let halloween = CelebrationPolicy.resolve(F.events, preferences: both, on: try F.day("2026-10-15"))
        #expect(halloween.active?.reason == .only)
        #expect(halloween.active?.appliesToAppIcon == true)
    }

    @Test func coreDatesOutrankAnExtendedWindow() throws {
        var both = F.enabled(F.halloween, F.muertos)
        both.selections[F.muertos]?.window = FirstPartyCelebrations.extended
        // Both decorative: the user's order (Halloween first, as enabled) decides.
        #expect(try F.active(both, on: "2026-10-28") == F.halloween)
        // Halloween's own day beats Día de Muertos' decorative window.
        let eve = CelebrationPolicy.resolve(F.events, preferences: both, on: try F.day("2026-10-31"))
        #expect(eve.active?.eventID == F.halloween)
        #expect(eve.active?.reason == .coreDates(over: F.muertos))
        #expect(try F.active(both, on: "2026-11-02") == F.muertos)
        #expect(try F.active(both, on: "2026-11-03") == F.halloween)
    }

    @Test func priorityDecidesBetweenEqualDays() throws {
        var both = F.enabled(F.halloween, F.muertos)
        both.selections[F.muertos]?.window = FirstPartyCelebrations.extended
        both.move(F.muertos, by: -1, in: F.events)
        #expect(both.order(in: F.events) == [F.muertos, F.halloween])
        let day = CelebrationPolicy.resolve(F.events, preferences: both, on: try F.day("2026-10-28"))
        #expect(day.active?.eventID == F.muertos)
        #expect(day.active?.reason == .priority(over: F.halloween))
        // Priority never overrides core dates.
        #expect(try F.active(both, on: "2026-10-31") == F.halloween)
    }

    @Test func catalogueOrderIsTheFallback() throws {
        var both = CelebrationPreferences()
        both.selections = [F.muertos: .init(isEnabled: true, window: FirstPartyCelebrations.extended), F.halloween: .init(isEnabled: true)]
        #expect(both.order(in: F.events) == [F.halloween, F.muertos])
        #expect(try F.active(both, on: "2026-10-29") == F.halloween)
    }

    @Test func skipThisOccurrence() throws {
        var both = F.enabled(F.halloween, F.muertos)
        both.skipped.insert(CelebrationOccurrence.ID(eventID: F.halloween, coreStart: try F.day("2026-10-31")))
        #expect(try F.active(both, on: "2026-10-15") == nil)
        #expect(try F.active(both, on: "2026-11-01") == F.muertos)
        #expect(try F.active(both, on: "2026-11-03") == nil)
        // Next year's Halloween is untouched.
        #expect(try F.active(both, on: "2027-10-15") == F.halloween)
        let skipped = CelebrationPolicy.resolve(F.events, preferences: both, on: try F.day("2026-10-15"))
        #expect(skipped.skipped.map(\.eventID) == [F.halloween])
    }

    @Test func temporaryChoiceComesFirst() throws {
        var both = F.enabled(F.halloween, F.muertos)
        both.chosen = CelebrationOccurrence.ID(eventID: F.halloween, coreStart: try F.day("2026-10-31"))
        let day = CelebrationPolicy.resolve(F.events, preferences: both, on: try F.day("2026-11-01"))
        #expect(day.active?.eventID == F.halloween)
        #expect(day.active?.reason == .chosen(over: F.muertos))
    }

    @Test func restoringTheBaseSkipsWhatsShowingToday() throws {
        var halloween = F.enabled(F.halloween)
        let today = CelebrationPolicy.resolve(F.events, preferences: halloween, on: try F.day("2026-10-18"))
        let showing = try #require(today.active?.occurrence)
        halloween.skipped.formUnion([showing.id] + today.runnersUp.map(\.id))
        #expect(try F.active(halloween, on: "2026-10-18") == nil)
        #expect(try F.active(halloween, on: "2026-11-07") == nil)
        #expect(try F.active(halloween, on: "2027-10-01") == F.halloween)
    }

    @Test func disabledPluginRestoresTheBase() throws {
        let halloween = F.enabled(F.halloween)
        let withoutPlugin = F.catalog().limited(toPlugins: [])
        let resolution = CelebrationPolicy.resolve(
            withoutPlugin.events, preferences: halloween, on: try F.day("2026-10-18"))
        #expect(resolution.active == nil)
        #expect(resolution.nextChange == nil)
        // The preference survives, so turning the plugin back on brings Halloween back.
        #expect(try F.active(halloween, on: "2026-10-18") == F.halloween)
    }

    @Test func missingArtworkOnlyAffectsItsSurface() throws {
        // No Beta dark icon compiled in: Halloween's icon is unavailable, Home still dresses up.
        let catalog = F.catalog { $0 != "AppIcon-halloween-beta-dark" }
        let event = try #require(catalog.event(F.halloween))
        #expect(event.appIcon == .unavailable("Missing Native Beta dark."))
        let resolution = CelebrationPolicy.resolve(
            catalog.events, preferences: F.enabled(F.halloween), on: try F.day("2026-10-18"))
        #expect(resolution.active?.appliesToAppIcon == false)
        #expect(resolution.active?.appliesToHome == true)

        // With Home switched off too, nothing applies, so Halloween can't hide another celebration.
        var iconOnly = F.enabled(F.halloween, F.muertos)
        iconOnly.selections[F.halloween]?.home = false
        #expect(try F.active(iconOnly, on: "2026-10-18", events: catalog.events) == nil)
        #expect(try F.active(iconOnly, on: "2026-11-01", events: catalog.events) == F.muertos)
    }

    @Test func platformsWithoutIconsKeepHome() throws {
        let day = CelebrationPolicy.resolve(
            F.events, preferences: F.enabled(F.halloween), on: try F.day("2026-10-18"), canApplyAppIcon: false)
        #expect(day.active?.eventID == F.halloween)
        #expect(day.active?.appliesToAppIcon == false)
    }

    @Test func switchedOffSurfacesAndEventsDoNothing() throws {
        #expect(try F.active(CelebrationPreferences(), on: "2026-10-31") == nil)
        var neither = F.enabled(F.halloween)
        neither.selections[F.halloween]?.appIcon = false
        neither.selections[F.halloween]?.home = false
        let resolution = CelebrationPolicy.resolve(F.events, preferences: neither, on: try F.day("2026-10-31"))
        #expect(resolution.active == nil)
        #expect(resolution.nextChange == nil)
    }

    @Test func removedWindowFallsBackWithoutRewritingTheChoice() throws {
        var halloween = F.enabled(F.halloween)
        halloween.selections[F.halloween]?.window = CelebrationWindow.ID("retired")
        #expect(try F.active(halloween, on: "2026-10-01") == F.halloween)
        #expect(halloween.selections[F.halloween]?.window == CelebrationWindow.ID("retired"))
    }

    @Test func pruningForgetsOldSkips() throws {
        var preferences = F.enabled(F.halloween)
        let old = CelebrationOccurrence.ID(eventID: F.halloween, coreStart: try F.day("2024-10-31"))
        let current = CelebrationOccurrence.ID(eventID: F.halloween, coreStart: try F.day("2026-10-31"))
        preferences.skipped = [old, current]
        preferences.prune(before: try F.day("2026-11-01"))
        #expect(preferences.skipped == [current])
    }
}
