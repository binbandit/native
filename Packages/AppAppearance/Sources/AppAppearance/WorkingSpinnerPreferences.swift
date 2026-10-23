import Foundation
import Observation

/// A task keeps its randomly chosen animation across turns, view recreation and app launches.
@MainActor @Observable
public final class WorkingSpinnerPreferences {
    public static let enabledKey = "appearance.playfulSpinners"
    private static let choicesKey = "appearance.workingAnimations"

    public private(set) var isEnabled: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let choose: () -> WorkingAnimation
    @ObservationIgnored private var choices: [String: [String: String]]

    public init(
        defaults: UserDefaults = .standard,
        choose: @escaping () -> WorkingAnimation = { WorkingAnimation.allCases.randomElement() ?? .sweep }
    ) {
        self.defaults = defaults
        self.choose = choose
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        choices = defaults.dictionary(forKey: Self.choicesKey) as? [String: [String: String]] ?? [:]
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    /// Called when the task model starts, never while a view draws. Agent IDs scope task IDs.
    public func animation(agentID: String, taskID: String) -> WorkingAnimation {
        if let saved = choices[agentID]?[taskID], let animation = WorkingAnimation(rawValue: saved) {
            return animation
        }
        let animation = choose()
        choices[agentID, default: [:]][taskID] = animation.rawValue
        defaults.set(choices, forKey: Self.choicesKey)
        return animation
    }
}
