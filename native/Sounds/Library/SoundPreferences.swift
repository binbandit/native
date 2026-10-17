import Foundation
import Observation

/// The user's sound choices, kept in `UserDefaults` under `sounds.*`.
@Observable
final class SoundPreferences {
    var selection: SoundID {
        didSet { defaults.set(selection.rawValue, forKey: Key.selection) }
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
        static let selection = "sounds.selection"
        static let volume = "sounds.volume"
        static let triggers = "sounds.triggers"
        static let timing = "sounds.timing"
        static let customSounds = "sounds.customSounds"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: Key.selection).flatMap(SoundID.init(rawValue:)) ?? .default
        volume = defaults.object(forKey: Key.volume) as? Double ?? Self.defaultVolume
        triggers = defaults.stringArray(forKey: Key.triggers).map { Set($0.compactMap(SoundTrigger.init(rawValue:))) }
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

    /// Forgets a custom sound (the file stays where it is). If it was selected, the default takes over.
    func removeCustomSound(_ id: UUID) {
        customSounds.removeAll { $0.id == id }
        if selection == .custom(id) {
            selection = .default
        }
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
