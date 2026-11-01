import Foundation

/// One process-wide gate before audio hardware is opened, including previews and test harnesses.
nonisolated enum NativeAudioPolicy {
    static let isMuted: Bool = {
        let defaults = UserDefaults.standard
        // bool(forKey:) accepts launch arguments (YES/NO strings) as well as stored booleans.
        if defaults.object(forKey: "native.mute") != nil {
            return defaults.bool(forKey: "native.mute")
        }
        #if DEBUG
        // Also covers Xcode previews and harnesses loading Native.debug.dylib without the launcher.
        return true
        #else
        return false
        #endif
    }()
}
