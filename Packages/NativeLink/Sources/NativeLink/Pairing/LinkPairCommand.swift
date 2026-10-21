import Foundation
import NativeHostProtocol

/// `"Native Host" pair`, run in a shell on a host without a screen (`ssh mac-mini`): opens a pairing
/// window through the gateway's control socket, prints a one-time link (5 minutes, single use) with
/// the host's key, name, addresses and the grants the pairing gives, and waits until a device pairs
/// with it or it expires, saying which. Add Host on a Mac runs it over SSH with `--json`.
///
/// Whoever runs it decides the grants up front, since nobody sits at the host to confirm: a device
/// that proves the link's secret pairs without asking (`LinkGateway.openPairingWindow(preapproving:)`).
/// Any process of this user can run it, so it gives only sessions unless asked for more, and the
/// host journals every pairing.
public struct LinkPairCommand: Sendable {
    public static let name = "pair"
    /// Only builds that have the command contain this string. Add Host looks for it in the helper
    /// before running it, because an older helper ignores its arguments and would start serving a
    /// host instead. Longer than 15 bytes, so Swift stores it as is rather than packed in code.
    public static let marker = "native-host-pair-command-v1"

    public static let usage = """
        usage: "Native Host" pair [--run-commands] [--install-updates] [--manage-plugins] [--json]

        Prints a one-time link (single use, 5 minutes) that pairs one device with this Mac's
        background host, then waits until a device uses it or it expires. Paste the link into
        Add Host in Native on your other Mac.

        The device can follow and drive tasks. It can do more only if you say so:
          --run-commands     run commands and read and write files in this host's projects
          --install-updates  install Native updates here and restart the host
          --manage-plugins   turn this host's plugins on and off
          --json             print one JSON object per line (Native's Add Host reads them)
        """

    public struct Options: Hashable, Sendable {
        public var grants = LinkGrants.standard
        public var printsJSON = false

        public init(grants: LinkGrants = .standard, printsJSON: Bool = false) {
            self.grants = grants
            self.printsJSON = printsJSON
        }
    }

    public struct UsageError: Error, CustomStringConvertible {
        public let description: String
    }

    public enum ExitStatus {
        public static let paired: Int32 = 0
        public static let failed: Int32 = 1
        public static let usage: Int32 = 64
    }

    /// Writes one line: to standard error when `isError`, else to standard output.
    public typealias Output = @Sendable (_ line: String, _ isError: Bool) -> Void

    /// Reads the arguments after `pair`.
    public static func parse(_ arguments: [String]) throws(UsageError) -> Options {
        var options = Options()
        for argument in arguments {
            switch argument {
            case "--run-commands": options.grants.runCommands = true
            case "--install-updates": options.grants.manageHost = true
            case "--manage-plugins": options.grants.managePlugins = true
            case "--json": options.printsJSON = true
            default: throw UsageError(description: "unknown option \(argument)")
            }
        }
        return options
    }

    let options: Options
    let hostDirectory: URL
    /// The Native build running the command: its version, for Add Host's version check.
    let build: PeerInfo
    let output: Output

    /// `hostDirectory` is the host location's directory, as for `LinkControlClient`.
    public init(options: Options, hostDirectory: URL, build: PeerInfo, output: @escaping Output) {
        self.options = options
        self.hostDirectory = hostDirectory
        self.build = build
        self.output = output
    }

    /// Runs until a device pairs or the link is spent, and returns the process's exit status.
    public func run() async -> Int32 {
        let control = LinkControlClient(hostDirectory: hostDirectory)
        await control.start()
        let status = await run(control)
        await control.stop()
        return status
    }

    private func run(_ control: LinkControlClient) async -> Int32 {
        var events = control.events.makeAsyncIterator()
        // The first event says whether the gateway answers at all.
        guard case .status = await events.next() else { return fail(.hostNotRunning) }
        let opened: LinkStatus
        do {
            opened = try await control.openPairingWindow(preapproving: options.grants)
        } catch {
            return fail(.hostNotRunning)
        }
        guard opened.isAllowedByPolicy != false, let pairing = opened.pairing, let grants = pairing.invite.grants
        else { return fail(.notAllowed) }

        // At the expiry the control connection is closed on purpose, which ends the events.
        let expiry = Task {
            try await Task.sleep(for: .seconds(max(pairing.expiresAt.timeIntervalSinceNow, 0)))
            await control.stop()
        }
        defer { expiry.cancel() }
        var sawWindow = false
        // The link carries the listener's port, so it goes out once the listener is bound.
        var announced = false
        if opened.listener.state != .starting {
            announce(pairing.invite, grants: grants)
            announced = true
        }
        while let event = await events.next() {
            guard case .status(let status) = event else { return fail(.hostStopped) }
            // Statuses from before the window opened can still be queued: wait for this window.
            guard let current = status.pairing, current.invite.secret == pairing.invite.secret else {
                if status.isAllowedByPolicy == false { return fail(.notAllowed) }
                if sawWindow { return fail(.replaced) }
                continue
            }
            sawWindow = true
            if !announced {
                if status.listener.state == .failed { return fail(.cannotListen, detail: status.listener.problem) }
                guard status.listener.state != .starting else { continue }
                announce(current.invite, grants: grants)
                announced = true
            }
            switch current.phase {
            case .paired:
                guard let device = status.devices.first(where: { $0.id == current.pairedDeviceID })?.device else {
                    continue
                }
                return paired(device)
            case .tooManyAttempts: return fail(.tooManyAttempts)
            case .expired: return fail(.expired)
            case .rejected: return fail(.replaced)
            case .open, .confirming, .unknown: continue
            }
        }
        return fail(.expired)
    }

    // MARK: - Output

    private func announce(_ invite: PairingInvite, grants: LinkGrants) {
        let link = invite.url.absoluteString
        guard !options.printsJSON else {
            return emit(
                LinkPairCommandEvent(
                    event: .invite, link: link, host: build, protocolVersion: HostProtocol.version, grants: grants))
        }
        let expiry = invite.expiresAt.formatted(date: .omitted, time: .shortened)
        let addresses = invite.addresses.map(\.label).joined(separator: ", ")
        output(
            """
            Pairing link for \(invite.hostName) (single use, expires at \(expiry)):

            \(link)

            Paste it into Add Host in Native on your other Mac. The device that pairs can \(grants.abilities).
            Reachable at \(addresses).

            Waiting for a device to pair. Press Control-C to cancel.
            """, false)
    }

    private func paired(_ device: LinkDevice) -> Int32 {
        if options.printsJSON {
            emit(
                LinkPairCommandEvent(
                    event: .paired,
                    device: LinkDeviceInfo(name: device.name, model: device.model, system: device.system),
                    grants: device.grants))
        } else {
            output(
                """
                Paired with “\(device.name)” (\(device.model) · \(device.system)). It can \(device.grants.abilities).
                Remove it in Native's Settings ▸ Paired Devices on this Mac, or forget this host on that one.
                """, false)
        }
        return ExitStatus.paired
    }

    private func fail(_ failure: LinkPairCommandEvent.Failure, detail: String? = nil) -> Int32 {
        let message = [Self.message(for: failure), detail].compactMap(\.self).joined(separator: " ")
        if options.printsJSON {
            emit(LinkPairCommandEvent(event: .failed, failure: failure, message: message))
        } else {
            output(message, true)
        }
        return ExitStatus.failed
    }

    private func emit(_ event: LinkPairCommandEvent) {
        output(event.line, false)
    }

    static func message(for failure: LinkPairCommandEvent.Failure) -> String {
        switch failure {
        case .hostNotRunning:
            "Native's background host isn't running on this Mac, so there's nothing to pair with. Open Native here once (its host keeps running after that), then run pair again."
        case .notAllowed:
            "The organization that manages this Mac turned off paired devices, so it can't pair."
        case .expired:
            "The link expired before a device used it. Run pair again for a new one."
        case .replaced:
            "Another pairing started on this Mac (Settings ▸ Paired Devices), which ended this link. Run pair again once it's done."
        case .tooManyAttempts:
            "Three attempts used the wrong link (an old one, or a guess), so this one is closed. Run pair again for a new link."
        case .hostStopped:
            "Native's background host stopped while the link was out. Run pair again once it's back."
        case .cannotListen:
            "Native's background host couldn't listen for devices on the network, so nothing could reach the link."
        case .unknown:
            "The pairing ended unexpectedly. Run pair again."
        }
    }
}
