/// When a triggered sound actually plays.
nonisolated enum SoundTiming: String, CaseIterable, Identifiable, Sendable {
    /// the reference app's policy: stay quiet only while the user is looking at that very session.
    case unlessViewing
    case inBackground
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlessViewing: "Unless I'm viewing it"
        case .inBackground: "Only in the background"
        case .always: "Always"
        }
    }

    /// Whether a sound plays now. "Viewing" means the session is on screen in the active app, so
    /// the user is already looking at what the sound would announce.
    func allows(isAppActive: Bool, isViewingSession: Bool) -> Bool {
        switch self {
        case .unlessViewing: !(isAppActive && isViewingSession)
        case .inBackground: !isAppActive
        case .always: true
        }
    }
}
