#if NATIVE_AGENT_PICKER_WIP
/// Where an agent stands for starting a session, in the words Home's cards and Settings use.
enum AgentPickerStatus: Equatable {
    case ready
    case starting
    case needsSignIn
    case signingIn
    case notInstalled
    case turnedOff
    case stopped

    init(_ availability: AgentAvailability) {
        self =
            switch availability {
            case .ready: .ready
            case .starting: .starting
            case .needsSignIn: .needsSignIn
            case .signingIn: .signingIn
            case .notInstalled: .notInstalled
            case .disabled: .turnedOff
            case .failed: .stopped
            }
    }

    var label: String {
        switch self {
        case .ready: "Ready"
        case .starting: "Starting…"
        case .needsSignIn: "Needs sign-in"
        case .signingIn: "Signing in…"
        case .notInstalled: "Not installed"
        case .turnedOff: "Turned off"
        case .stopped: "Stopped"
        }
    }

    /// On its way somewhere, which a loader shows beside the label.
    var isInProgress: Bool {
        self == .starting || self == .signingIn
    }

    /// Waiting on the user, which sets the label in the attention color.
    var needsUser: Bool {
        switch self {
        case .needsSignIn, .notInstalled, .turnedOff, .stopped: true
        case .ready, .starting, .signingIn: false
        }
    }
}
#endif
