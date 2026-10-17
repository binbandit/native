import Foundation
import SwiftUI

/// Which release of Native this is. Nightly builds carry small tells (stars on the home page, a quiet
/// mark in the window) so it's always clear features may still change.
enum ReleaseChannel: String, CaseIterable, Sendable {
    case stable
    case beta
    case nightly

    /// Set at build time: nightly and beta builds add `NATIVE_NIGHTLY` or `NATIVE_BETA` to
    /// `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. Developers can preview a channel without a special
    /// build: `defaults write <bundle id> releaseChannelOverride nightly`.
    static let current: ReleaseChannel = {
        if let override = UserDefaults.standard.string(forKey: "releaseChannelOverride"),
           let channel = ReleaseChannel(rawValue: override) {
            return channel
        }
        #if NATIVE_NIGHTLY
        return .nightly
        #elseif NATIVE_BETA
        return .beta
        #else
        return .stable
        #endif
    }()

    var displayName: String {
        switch self {
        case .stable: "Native"
        case .beta: "Native Beta"
        case .nightly: "Native Nightly"
        }
    }

    var isNightly: Bool { self == .nightly }
}

extension EnvironmentValues {
    @Entry var releaseChannel: ReleaseChannel = .current
}
