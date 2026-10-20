import Foundation
import NativeHostProtocol

/// One line `pair --json` prints: Add Host on a Mac runs the command over SSH and reads these.
/// First the link (`invite`), then how it ended (`paired` or `failed`).
public struct LinkPairCommandEvent: Codable, Hashable, Sendable {
    public enum Kind: String, WireEnum {
        case invite, paired, failed, unknown
    }

    /// Why no device paired.
    public enum Failure: String, WireEnum {
        /// The background host (and so its gateway) isn't running.
        case hostNotRunning
        /// The organization that manages the host turned paired devices off.
        case notAllowed
        /// Nobody used the link in time.
        case expired
        /// Someone opened another pairing window on the host, which replaces this one.
        case replaced
        /// Three wrong secrets: something is guessing.
        case tooManyAttempts
        /// The background host stopped while the link was out.
        case hostStopped
        /// The gateway couldn't listen on the network, so no device could reach the link.
        case cannotListen
        case unknown
    }

    public var event: Kind
    /// `invite`: the link.
    public var link: String?
    /// `invite`: the Native build that answered, to tell a version mismatch apart.
    public var host: PeerInfo?
    /// `invite`: the host protocol it speaks (`HostProtocol.version`).
    public var protocolVersion: Int?
    /// `paired`: who paired.
    public var device: LinkDeviceInfo?
    /// `paired`: what the pairing gave.
    public var grants: LinkGrants?
    public var failure: Failure?
    /// `failed`: what the command told its user.
    public var message: String?

    public init(
        event: Kind, link: String? = nil, host: PeerInfo? = nil, protocolVersion: Int? = nil,
        device: LinkDeviceInfo? = nil, grants: LinkGrants? = nil, failure: Failure? = nil, message: String? = nil
    ) {
        self.event = event
        self.link = link
        self.host = host
        self.protocolVersion = protocolVersion
        self.device = device
        self.grants = grants
        self.failure = failure
        self.message = message
    }

    /// One line of output, or nil for a line that isn't an event (anything a remote shell printed).
    public init?(line: String) {
        guard line.hasPrefix("{"), let event = try? JSONDecoder().decode(Self.self, from: Data(line.utf8)) else {
            return nil
        }
        self = event
    }

    public var line: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? #"{"event":"unknown"}"#
    }
}
