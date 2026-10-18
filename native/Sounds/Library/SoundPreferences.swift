import Foundation
import Observation

/// The user's sound choices, kept in `UserDefaults` under `sounds.*`.
@Observable
final class SoundPreferences {
    /// The one switch for every sound Native plays.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }

    /// Stay silent while Do Not Disturb or another Focus is on (when Native can tell).
    var staysQuietDuringFocus: Bool {
        didSet { defaults.set(staysQuietDuringFocus, forKey: Key.staysQuietDuringFocus) }
    }

    /// Each trigger's sound. Missing ones use the trigger's default.
    private var sounds: [SoundTrigger: SoundID] {
        didSet {
            for (trigger, sound) in sounds where oldValue[trigger] != sound {
                defaults.set(sound.rawValue, forKey: Key.sound(trigger))
            }
        }
    }

    /// 0...1. At the default, Native's sounds play at the level Conductor plays its chime.
    var volume: Double {
        didSet { defaults.set(volume, forKey: Key.volume) }
    }

    var triggers: Set<SoundTrigger> {
        didSet { defaults.set(triggers.map(\.rawValue).sorted(), forKey: Key.triggers) }
    }

    var timing: SoundTiming {
        didSet { defaults.set(timing.rawValue, forKey: Key.timing) }
    }

    private(set) var customSounds: [CustomSound] {
        didSet { defaults.set(try? JSONEncoder().encode(customSounds), forKey: Key.customSounds) }
    }

    static let defaultVolume = 0.7

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let enabled = "sounds.enabled"
        static let staysQuietDuringFocus = "sounds.staysQuietDuringFocus"
        static func sound(_ trigger: SoundTrigger) -> String { "sounds.sound.\(trigger.rawValue)" }
        /// Before each trigger had its own sound, one sound played for all of them.
        static let legacySelection = "sounds.selection"
        static let volume = "sounds.volume"
        static let triggers = "sounds.triggers"
        static let timing = "sounds.timing"
        static let customSounds = "sounds.customSounds"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        staysQuietDuringFocus = defaults.object(forKey: Key.staysQuietDuringFocus) as? Bool ?? true
        // The one sound earlier versions played stays the task-finished sound; the others get
        // their own new defaults.
        let legacy = defaults.string(forKey: Key.legacySelection).flatMap(SoundID.init(rawValue:))
        sounds = Dictionary(uniqueKeysWithValues: SoundTrigger.allCases.map { trigger in
            let stored = defaults.string(forKey: Key.sound(trigger)).flatMap(SoundID.init(rawValue:))
            return (trigger, stored ?? (trigger == .taskFinished ? legacy : nil) ?? trigger.defaultSound)
        })
        volume = defaults.object(forKey: Key.volume) as? Double ?? Self.defaultVolume
        triggers = defaults.stringArray(forKey: Key.triggers).map { Set($0.compactMap(SoundTrigger.init(storedValue:))) }
            ?? Set(SoundTrigger.allCases)
        timing = defaults.string(forKey: Key.timing).flatMap(SoundTiming.init(rawValue:)) ?? .unlessViewing
        customSounds = defaults.data(forKey: Key.customSounds).flatMap { try? JSONDecoder().decode([CustomSound].self, from: $0) } ?? []
    }

    /// Remembers files the user picked and returns them, skipping ones already added.
    @discardableResult
    func addCustomSounds(at urls: [URL]) -> [CustomSound] {
        let known = Set(customSounds.map(\.path))
        let added = urls.filter { !known.contains($0.path(percentEncoded: false)) }.map(CustomSound.init(url:))
        customSounds += added
        return added
    }

    /// Forgets a custom sound (the file stays where it is). Triggers that used it go back to their
    /// own default.
    func removeCustomSound(_ id: UUID) {
        customSounds.removeAll { $0.id == id }
        for (trigger, sound) in sounds where sound == .custom(id) {
            sounds[trigger] = trigger.defaultSound
        }
    }

    func sound(for trigger: SoundTrigger) -> SoundID {
        sounds[trigger] ?? trigger.defaultSound
    }

    func setSound(_ sound: SoundID, for trigger: SoundTrigger) {
        sounds[trigger] = sound
    }

    func isEnabled(_ trigger: SoundTrigger) -> Bool {
        triggers.contains(trigger)
    }

    func setEnabled(_ enabled: Bool, for trigger: SoundTrigger) {
        if enabled {
            triggers.insert(trigger)
        } else {
            triggers.remove(trigger)
        }
    }
}
