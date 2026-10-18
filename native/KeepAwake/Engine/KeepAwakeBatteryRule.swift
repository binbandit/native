/// What keeping awake does on battery power. Stopping below 10% is the default, so a forgotten
/// keep-awake never drains the battery flat.
nonisolated enum KeepAwakeBatteryRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case keepAwake
    case stopWhenLow
    case pluggedInOnly

    var id: String { rawValue }

    /// Below this share of charge, `stopWhenLow` lets the Mac sleep.
    static let lowBattery = 0.1

    var title: String {
        switch self {
        case .keepAwake: "Keep awake"
        case .stopWhenLow: "Stop below 10%"
        case .pluggedInOnly: "Don't keep awake"
        }
    }
}
