import IOKit.pwr_mgt

/// The power assertions keeping awake takes, the same ones `caffeinate` takes for its flags.
nonisolated enum PowerAssertionKind: CaseIterable, Hashable, Sendable {
    /// `caffeinate -i`: no idle sleep, on battery too. The display may still sleep.
    case preventIdleSleep
    /// `caffeinate -s`: no system sleep at all while on power. macOS ignores it on battery, and
    /// closing the lid still sleeps the Mac.
    case preventSystemSleep
    /// `caffeinate -d`: the display stays on.
    case preventDisplaySleep

    var type: String {
        switch self {
        case .preventIdleSleep: kIOPMAssertionTypePreventUserIdleSystemSleep
        case .preventSystemSleep: kIOPMAssertionTypePreventSystemSleep
        case .preventDisplaySleep: kIOPMAssertionTypePreventUserIdleDisplaySleep
        }
    }
}
