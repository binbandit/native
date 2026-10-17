import Foundation

/// The releases a user follows. Stable builds choose Stable or Beta (a Sparkle channel in the same
/// feed); Native Nightly is a separate app with its own feed, so its channel is fixed.
enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable
    case beta
    case nightly

    static let storageKey = "updateChannel"

    var id: Self { self }

    var title: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        case .nightly: "Nightly"
        }
    }

    var summary: String {
        switch self {
        case .stable: "Tested releases."
        case .beta: "Upcoming features a few weeks early. Expect rough edges."
        case .nightly: "A build of the latest changes, every night. Features may change or break."
        }
    }

    /// Sparkle channels whose items this user may install. Stable items have no channel and are
    /// always allowed, so beta users still get stable releases newer than their beta.
    var sparkleChannels: Set<String> {
        self == .beta ? ["beta"] : []
    }

    /// The channels a build can offer: nightly builds stay nightly.
    static func choices(for build: ReleaseChannel) -> [UpdateChannel] {
        build.isNightly ? [.nightly] : [.stable, .beta]
    }

    /// The user's choice, defaulting to the channel the build came from (a beta build follows beta).
    static func preferred(for build: ReleaseChannel, defaults: UserDefaults = .standard) -> UpdateChannel {
        if build.isNightly { return .nightly }
        if let stored = defaults.string(forKey: storageKey).flatMap(UpdateChannel.init(rawValue:)), stored != .nightly {
            return stored
        }
        return build == .beta ? .beta : .stable
    }
}
