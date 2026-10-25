#if os(macOS)
import CoreFoundation
import CryptoKit
import Foundation
import NativeHost
import NativeHostProtocol
import NativePolicy
import Synchronization
import Testing

@testable import NativeHostMac

/// Where a Mac host reads its policy, what it makes of it, and the standalone updater's managed
/// mirror (docs/enterprise/host-policy.md). Profiles are stood in for: nothing here reads a real
/// profile or the installed app's domain.
@Suite("Mac host policy")
struct MacHostPolicyTests {
    static func policy(
        managed: [String: Any] = [:], user: [String: Any] = [:], status: ManagedSourceStatus = .available,
        enrollment: (any PolicyEnrollmentStore)? = nil, channel: String = "stable"
    ) -> HostPolicy {
        nonisolated(unsafe) let managed = managed
        nonisolated(unsafe) let user = user
        return MacHostPolicySource(channel: channel) {
            StaticPolicySource(managed: managed, user: user, status: status, enrollment: enrollment)
        }.current()
    }

    @Test("With nothing managed the host is unrestricted, as before")
    func unmanaged() {
        #expect(Self.policy() == .unrestricted)
    }

    @Test("Malformed, unreadable or unknown managed policy blocks the host")
    func lockdowns() {
        #expect(Self.policy(managed: ["policy.deployment.mode": 42]).mode == .blocked)
        #expect(Self.policy(managed: ["policy.deployment.mode": "sealed"]).mode == .blocked)
        #expect(Self.policy(status: .unavailable).mode == .blocked)
        #expect(Self.policy(managed: ["policy.deployment.mode": "airGapped", "policy.made.up": true]).mode == .blocked)
        #expect(Self.policy(status: .unavailable).reason == "Its managed policy can't be read.")
    }

    @Test("An ordinary policy turns off what its keys turn off, and a malformed value denies it")
    func ordinaryKeys() {
        func lacks(_ capability: HostCapability, _ managed: [String: Any], channel: String = "stable") -> Bool {
            let policy = Self.policy(managed: managed, channel: channel)
            return policy.mode == .ordinary && !policy.allows(capability)
                && policy.capabilities == Set(HostCapability.allCases).subtracting([capability])
        }
        #expect(lacks(.companion, ["policy.companion.enabled": false]))
        #expect(lacks(.companion, ["policy.companion.enabled": "no"]))
        #expect(lacks(.updates, ["policy.updates.enabled": false]))
        #expect(lacks(.updates, ["policy.updates.channels": ["stable"]], channel: "beta"))
        #expect(lacks(.updates, ["policy.updates.feedURL": "not a feed"]))
        #expect(lacks(.agents, ["policy.agents.allowed": 42]))
        // The organization's false beats the user's true.
        #expect(
            Self.policy(managed: ["policy.companion.enabled": false], user: ["policy.companion.enabled": true])
                .allows(.companion) == false)
    }

    @Test("A restricted policy allows nothing that isn't qualified for it yet")
    func restricted() {
        for mode in ["internalOnly", "airGapped"] {
            let policy = Self.policy(managed: ["policy.deployment.mode": mode, "policy.companion.enabled": true])
            #expect(policy.mode == .restricted)
            #expect(!policy.allows(.agents) && !policy.allows(.loginShell) && !policy.allows(.updates))
        }
    }

    @Test("Removing a restricted profile blocks the host across restarts, until the organization deploys ordinary")
    func removalAfterEnrollment() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "host-enrollment-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "policy-enrollment.json")
        let restricted: [String: Any] = ["policy.deployment.mode": "internalOnly"]

        #expect(Self.policy(managed: restricted, enrollment: FilePolicyEnrollmentStore(url: file)).mode == .restricted)
        // Each store stands for a new run of the host, reading what the last one left.
        let removed = Self.policy(enrollment: FilePolicyEnrollmentStore(url: file))
        #expect(removed.mode == .blocked)
        #expect(removed.reason?.contains("only the organization deploying ordinary mode lifts it") == true)
        let userAsksOrdinary = Self.policy(
            user: ["policy.deployment.mode": "ordinary"], enrollment: FilePolicyEnrollmentStore(url: file))
        #expect(userAsksOrdinary.mode == .blocked)
        #expect(
            Self.policy(
                managed: ["policy.deployment.mode": "ordinary"], enrollment: FilePolicyEnrollmentStore(url: file))
                == .unrestricted)
        #expect(Self.policy(enrollment: FilePolicyEnrollmentStore(url: file)) == .unrestricted)
    }

    @Test("A managed appcast mirror gives the host feed beside it")
    func mirrorFeed() {
        let source = MacHostPolicySource(channel: "beta") {
            StaticPolicySource(managed: [
                "policy.updates.feedURL": "https://updates.example.internal/native/appcast.xml"
            ])
        }
        #expect(
            source.updateFeedURL()?.absoluteString == "https://updates.example.internal/native/host-feed-beta.json")
        #expect(MacHostPolicySource(channel: "stable") { StaticPolicySource() }.updateFeedURL() == nil)
    }

    @Test("The host reads its app's domain from outside the app, fresh each time")
    func readsAnotherDomain() {
        let domain = "dev.binbandit.native.tests.host-policy-\(UUID().uuidString)" as CFString
        let key = "policy.companion.enabled" as CFString
        defer {
            CFPreferencesSetAppValue(key, nil, domain)
            CFPreferencesAppSynchronize(domain)
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences/\(domain).plist")
            try? FileManager.default.removeItem(at: file)
        }
        let source = MacHostPolicySource(
            domain: domain as String, channel: "stable", enrollment: MemoryPolicyEnrollmentStore())
        #expect(source.current() == .unrestricted)

        CFPreferencesSetAppValue(key, kCFBooleanFalse, domain)
        CFPreferencesAppSynchronize(domain)
        #expect(!source.current().allows(.companion))
    }

    @Test("The helper reads its app's domain, a standalone release its channel's, a local build none")
    func domains() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "host-domains-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ identifier: String?) throws -> Bundle {
            let contents = root.appending(path: "\(UUID().uuidString).app/Contents", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = identifier.map { ["CFBundleIdentifier": $0] } ?? [:]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
            return try #require(Bundle(url: contents.deletingLastPathComponent()))
        }

        #expect(
            MacHostPolicySource.domain(bundle: try bundle("dev.binbandit.native.Host"), channel: "stable")
                == "dev.binbandit.native")
        #expect(
            MacHostPolicySource.domain(bundle: try bundle("dev.binbandit.native.dev.alice.Host"), channel: "")
                == "dev.binbandit.native.dev.alice")
        #expect(
            MacHostPolicySource.domain(bundle: try bundle("native-host"), channel: "beta") == "dev.binbandit.native")
        #expect(
            MacHostPolicySource.domain(bundle: try bundle("native-host"), channel: "nightly")
                == "dev.binbandit.native.nightly")
        #expect(MacHostPolicySource.domain(bundle: try bundle(nil), channel: "stable") == nil)
        #expect(MacHostPolicySource.domain(bundle: try bundle("com.example.other"), channel: "stable") == nil)
    }

    @Test("A managed mirror moves a standalone host's checks there, with no fallback to the built-in feed")
    func mirrorHasNoFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "host-mirror-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fetched = Mutex<[URL]>([])
        let mirror = Mutex<URL?>(URL(string: "https://updates.example.internal/native/host-feed.json"))
        let info: [String: Any] = [
            "NativeHostFeedURL": "https://github.com/binbandit/native/releases/latest/download/host-feed.json",
            "SUPublicEDKey": Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
        ]
        let made = StandaloneHostUpdater(
            info: info, root: root, runningBuild: "100", mirror: { mirror.withLock { $0 } },
            fetch: { url in
                fetched.withLock { $0.append(url) }
                throw URLError(.cannotConnectToHost)
            })
        let updater = try #require(made)

        await #expect(throws: (any Error).self) { _ = try await updater.checkAndStage() }
        #expect(!fetched.withLock { $0 }.isEmpty)
        #expect(fetched.withLock { $0 }.allSatisfy { $0.host() == "updates.example.internal" })

        // Without a mirror the built-in feed is used again.
        mirror.withLock { $0 = nil }
        fetched.withLock { $0 = [] }
        await #expect(throws: (any Error).self) { _ = try await updater.checkAndStage() }
        #expect(fetched.withLock { $0 }.allSatisfy { $0.host() == "github.com" })
    }
}
#endif
