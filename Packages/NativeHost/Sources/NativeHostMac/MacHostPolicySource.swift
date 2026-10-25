import CoreFoundation
import Foundation
import HostUpdater
import NativeHost
import NativePolicy

/// A Mac host's policy, read by the host itself from the managed preferences of Native's
/// preference domain (docs/enterprise/host-policy.md), so the same configuration profile that
/// manages Native.app manages its host, whether the app runs or not. `NativePolicy` resolves it, so
/// the host and the app agree on every key, on malformed input and on restricted enrollment.
public struct MacHostPolicySource: HostPolicySource {
    /// The update channel this host is on, for `policy.updates.channels`.
    let channel: String
    /// A fresh read of the domain each time: the app and profiles change it from outside the host.
    let source: @Sendable () -> any PolicySource

    /// `enrollment` keeps a restricted deployment across restarts in the host's own directory, so
    /// removing the profile while no app runs doesn't lift it either (`PolicyEnrollment`).
    public init(domain: String, channel: String, enrollment: any PolicyEnrollmentStore) {
        self.init(channel: channel) { PreferenceDomainPolicySource(domain: domain, enrollment: enrollment) }
    }

    /// Tests stand in for a configuration profile, which they can't install.
    init(channel: String, source: @escaping @Sendable () -> any PolicySource) {
        self.channel = channel
        self.source = source
    }

    /// The domain this process's host reads. The helper inside Native.app (`<app id>.Host`) reads
    /// its app's, so a development build's host reads its own build's. A standalone release
    /// `native-host` names no app, so it reads the release app's of its channel
    /// (`Config/Shared.xcconfig`, `NATIVE_BUNDLE_IDENTIFIER`). Nil for a binary without a bundle
    /// identifier (`swift build`, tests), which no organization manages.
    public static func domain(bundle: Bundle = .main, channel: String) -> String? {
        guard let identifier = bundle.bundleIdentifier else { return nil }
        if identifier.hasSuffix(".Host") {
            return String(identifier.dropLast(".Host".count))
        }
        guard identifier == "native-host" else { return nil }
        return channel == "nightly" ? "dev.binbandit.native.nightly" : "dev.binbandit.native"
    }

    public func current() -> HostPolicy {
        Self.hostPolicy(from: PolicyLoader.load(from: source()), channel: channel)
    }

    /// The host feed of the organization's update mirror (`policy.updates.feedURL`, which points at
    /// its appcast), or nil when no mirror is managed. Read at each check, so it follows the profile.
    public func updateFeedURL() -> URL? {
        PolicyLoader.load(from: source()).updates.feedURL.map {
            HostUpdateSource.feedURL(besideAppcast: $0, channel: channel)
        }
    }

    /// What `policy` allows a host on `channel`. Each capability follows the decision the app makes
    /// for the same feature, so an invalid managed value denies it here as it does there.
    static func hostPolicy(from policy: NativePolicy, channel: String) -> HostPolicy {
        if let lockdown = policy.deployment.lockdown {
            return .blocked(reason(lockdown))
        }
        func permits(_ capability: PolicyCapability) -> Bool {
            policy.decision(for: capability).isPermitted
        }
        // A mirror that's malformed must not leave the built-in feed in its place.
        let updates =
            permits(.hostUpdates) && policy.updates.allows(channel: channel)
            && policy.keyStatus[.updatesFeedURL]?.validity.isFailure != true
        guard !policy.isRestricted else {
            return HostPolicy(
                mode: .restricted, capabilities: permits(.pairing) ? [.companion] : [],
                reason: "It's in a restricted deployment, where this isn't available yet.")
        }
        var capabilities = Set(HostCapability.allCases)
        let decided: [(HostCapability, Bool)] = [
            (.agents, permits(.agentExecution)), (.agentTools, permits(.orchestration)),
            (.companion, permits(.pairing)), (.updates, updates),
        ]
        for (capability, isPermitted) in decided where !isPermitted {
            capabilities.remove(capability)
        }
        // The app filters its catalog by the same list; the host holds to it for every client.
        return HostPolicy(mode: .ordinary, capabilities: capabilities, allowedAgents: policy.agents.allowed)
    }

    /// Why a locked-down policy blocks the host, without any of its values.
    private static func reason(_ lockdown: NativePolicy.Deployment.Lockdown) -> String {
        switch lockdown {
        case .malformed: "Its managed policy is malformed."
        case .unavailable: "Its managed policy can't be read."
        case .invalidMode: "Its managed deployment mode isn't one Native knows."
        case .removedAfterEnrollment:
            "Its restricted policy was removed, and only the organization deploying ordinary mode lifts it."
        case .unknownKeys: "Its restricted policy sets keys this version of Native doesn't know."
        }
    }
}

/// Another process's preference domain as cfprefsd serves it: a value a configuration profile
/// forces is the organization's, any other is the user's. Launch arguments never reach another
/// domain, so they can't stand in for either.
struct PreferenceDomainPolicySource: PolicySource {
    let domain: String
    let enrollment: (any PolicyEnrollmentStore)?

    init(domain: String, enrollment: (any PolicyEnrollmentStore)?) {
        self.domain = domain
        self.enrollment = enrollment
        CFPreferencesAppSynchronize(domain as CFString)
    }

    func managedEntry(forKey key: String) -> ManagedEntry {
        guard CFPreferencesAppValueIsForced(key as CFString, domain as CFString) else { return .absent }
        // Forced, yet nothing to read: never guess what the organization meant.
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return .unreadable }
        return .value(value)
    }

    func userValue(forKey key: String) -> Any? {
        guard !CFPreferencesAppValueIsForced(key as CFString, domain as CFString) else { return nil }
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    /// cfprefsd can't list only the forced keys of a domain.
    var managedKeys: [String]? { nil }
}
