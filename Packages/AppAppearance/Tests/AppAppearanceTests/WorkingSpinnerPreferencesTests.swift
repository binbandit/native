import Foundation
import Testing

@testable import AppAppearance

@Suite @MainActor
struct WorkingSpinnerPreferencesTests {
    @Test func taskChoiceSurvivesTurnsTogglesAndRelaunch() throws {
        let domain = "WorkingSpinnerPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var choices = 0
        let preferences = WorkingSpinnerPreferences(defaults: defaults) {
            choices += 1
            return .snake
        }
        #expect(!preferences.isEnabled)
        #expect(preferences.animation(agentID: "agent", taskID: "one") == .snake)
        preferences.setEnabled(true)
        #expect(preferences.animation(agentID: "agent", taskID: "one") == .snake)
        preferences.setEnabled(false)
        preferences.setEnabled(true)
        #expect(preferences.animation(agentID: "agent", taskID: "one") == .snake)
        #expect(choices == 1)

        let reopened = WorkingSpinnerPreferences(defaults: defaults) { .rain }
        #expect(reopened.isEnabled)
        #expect(reopened.animation(agentID: "agent", taskID: "one") == .snake)
        #expect(reopened.animation(agentID: "agent", taskID: "two") == .rain)
        #expect(reopened.animation(agentID: "other", taskID: "one") == .rain)
        reopened.setEnabled(false)
        #expect(!WorkingSpinnerPreferences(defaults: defaults).isEnabled)
    }

    @Test func unknownSavedChoiceIsReplacedOnce() throws {
        let domain = "WorkingSpinnerPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["agent": ["task": "removed-pattern"]], forKey: "appearance.workingAnimations")
        let preferences = WorkingSpinnerPreferences(defaults: defaults) { .ripple }
        #expect(preferences.animation(agentID: "agent", taskID: "task") == .ripple)
        let reopened = WorkingSpinnerPreferences(defaults: defaults) { .orbit }
        #expect(reopened.animation(agentID: "agent", taskID: "task") == .ripple)
    }
}
