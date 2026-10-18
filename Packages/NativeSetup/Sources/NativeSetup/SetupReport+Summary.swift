import Foundation

extension SetupReport {
    /// The report as a numbered checklist, in the order the `set-up-native` skill walks through it:
    /// Native, agents, the durable host, paired devices, the organization, updates. Each line says
    /// what's wrong and where the user fixes it, in Settings' own words.
    public var summary: String {
        [nativeLine, agentsSection, hostLine, devicesLine, organizationLine, updatesLine].joined(separator: "\n\n")
    }

    private var nativeLine: String {
        switch native.channel {
        case .dev: "1. Native: \(native.version) (\(native.build)), a development build run from source."
        case .stable: "1. Native: \(native.version) (\(native.build)), Stable."
        case .beta: "1. Native: \(native.version) (\(native.build)), Beta."
        case .nightly: "1. Native: \(native.version) (\(native.build)), Native Nightly."
        }
    }

    private var agentsSection: String {
        guard !agents.isEmpty else { return "2. Agents: none. Every plugin that provides one is missing." }
        let ready = agents.filter { $0.state == .ready && $0.signIn != .needsSignIn }.count
        let lines = agents.map { "- \($0.name) (`\($0.id)`): \($0.status)" }
        return (["2. Agents (\(ready) of \(agents.count) ready):"] + lines).joined(separator: "\n")
    }

    private var hostLine: String {
        "3. Durable host: " + durableHost.status
    }

    private var devicesLine: String {
        "4. Paired devices: " + pairedDevices.status
    }

    private var organizationLine: String {
        var line =
            organization.managedKeys.isEmpty
            ? "5. Organization: manages nothing on this Mac."
            : "5. Organization: manages \(Self.list(organization.managedKeys)). Those settings are locked in Settings."
        if !organization.ignoredKeys.isEmpty {
            line += " Ignored values it couldn't use for \(Self.list(organization.ignoredKeys))."
        }
        return line
    }

    private var updatesLine: String {
        "6. Updates: " + updates.status
    }

    static func list(_ keys: [String]) -> String {
        keys.map { "`\($0)`" }.joined(separator: ", ")
    }
}

extension SetupReport.Agent {
    fileprivate var status: String {
        var parts: [String]
        switch state {
        case .ready:
            parts = [readiness]
            if let version { parts.append("Reports \(version).") }
        case .starting:
            parts = ["starting.", "Runs `\(launch)`."]
        case .stopped:
            parts = [
                sentence("stopped", problem), "Runs `\(launch)`.",
                "Restart it from the ⋯ menu on its row in Settings ▸ Agents.",
            ]
        case .notInstalled:
            parts = ["not installed: `\(missingCommand ?? launch)` isn't on the login shell's PATH."]
            if let installCommand { parts.append("Install with `\(installCommand)`.") }
            parts.append("Then Settings ▸ Agents ▸ Add an Agent ▸ Check Again.")
        case .turnedOff:
            parts = ["turned off in Settings ▸ Agents."]
        case .notAllowed:
            parts = ["not allowed by the organization."]
        }
        if isCaller { parts.append("This session runs on it.") }
        return parts.joined(separator: " ")
    }

    private var readiness: String {
        switch signIn {
        case .signedIn: "ready and signed in."
        case .signingIn: "ready, signing in."
        case .unknown: "ready. Whether it's signed in shows once a session starts on it."
        case .needsSignIn where offersSignIn:
            "signed out. Sign In… from the ⋯ menu on its row in Settings ▸ Agents"
                + (signInCommand.map { ", or run `\($0)` in a terminal." } ?? ".")
        case .needsSignIn:
            "signed out. " + (signInCommand.map { "Run `\($0)` in a terminal to sign in, then" } ?? "Sign in, then")
                + " Restart \(name) from the ⋯ menu on its row in Settings ▸ Agents."
        }
    }
}

extension SetupReport.DurableHost {
    fileprivate var status: String {
        switch state {
        case .off:
            "off, so paired devices can't connect and nothing keeps running after Native quits. Turn it on in Window ▸ Durable Sessions ▸ Turn On."
        case .starting: "starting."
        case .connected:
            "connected" + (version.map { ", Native \($0)." } ?? ".") + versionNote
        case .reconnecting: "reconnecting."
        case .unreachable: sentence("not reachable", problem) + " Native keeps trying."
        case .incompatible:
            "speaks another protocol version" + (version.map { " (Native \($0))" } ?? "") + "." + versionNote
        case .needsApproval:
            "needs approval. Native is switched off in System Settings ▸ General ▸ Login Items & Extensions ▸ Allow in the Background."
        case .failed: sentence("didn't start", problem)
        }
    }

    private var versionNote: String {
        switch versionStatus {
        case .matched: ""
        case .restartPending: " It runs an older build and switches to this one once its tasks finish."
        case .appOutdated: " It's newer than this copy of Native: update Native."
        }
    }
}

extension SetupReport.PairedDevices {
    fileprivate var status: String {
        var parts: [String]
        switch state {
        case .hostOff:
            parts = ["unavailable while the durable host is off; the pairing gateway runs in it."]
        case .waitingForHost:
            parts = [sentence("waiting for the durable host", problem)]
        case .available:
            parts = ["\(paired ?? 0) paired, \(connected ?? 0) connected."]
            if acceptsConnections == false {
                parts.append("Connections are off (Settings ▸ Paired Devices ▸ Allow paired devices to connect).")
            }
            parts.append(listenerNote)
            if pairingOpen { parts.append("A pairing code is showing on the Mac.") }
        }
        if !allowedByOrganization { parts.append("The organization turned paired devices off.") }
        return parts.joined(separator: " ")
    }

    private var listenerNote: String {
        switch listener {
        case .listening: "The gateway is listening on the network."
        case .starting: "The gateway is starting."
        case .failed: sentence("The gateway couldn't listen", problem)
        case .off, nil: "Nothing listens on the network until a device is paired or Pair iPhone… is open."
        case .unknown: "The gateway's state is unknown."
        }
    }
}

extension SetupReport.Updates {
    fileprivate var status: String {
        let version = availableVersion.map { "Native \($0)" } ?? "an update"
        let state: String =
            switch self.state {
            case .idle: "nothing to do."
            case .checking: "checking now."
            case .upToDate: "up to date."
            case .available: "\(version) is available (Settings ▸ Updates ▸ Update)."
            case .downloading: "downloading \(version)."
            case .ready: "\(version) is ready and installs when Native quits, or with Restart to Update."
            case .installing: "installing \(version)."
            case .failed: sentence("the last attempt failed", message)
            case .unavailable: sentence("off", message)
            }
        var parts = [state]
        if let lastChecked { parts.append("Last checked \(lastChecked.formatted(.iso8601)).") }
        if self.state != .unavailable {
            parts.append(
                "\(channel.rawValue.capitalized) channel; checks automatically: \(automaticChecks ? "on" : "off"); downloads automatically: \(automaticDownloads ? "on" : "off")."
            )
        }
        return parts.joined(separator: " ")
    }
}

/// `lead: detail.`, or `lead.` without one, whether or not the detail ends with a period.
private func sentence(_ lead: String, _ detail: String?) -> String {
    guard let detail, !detail.isEmpty else { return lead + "." }
    return "\(lead): \(detail)" + (detail.hasSuffix(".") || detail.hasSuffix("…") ? "" : ".")
}
