import Foundation

/// A device the gateway just paired, for the host's activity journal: anyone who can run the host's
/// `pair` hands out a pairing nobody confirms on a screen, so every pairing is written down.
public struct LinkPairingRecord: Hashable, Sendable {
    public let device: LinkDevice
    /// Paired with a link whose grants were decided when it was made (`pair`), not confirmed on a screen.
    public let wasPreapproved: Bool

    public init(device: LinkDevice, wasPreapproved: Bool) {
        self.device = device
        self.wasPreapproved = wasPreapproved
    }

    /// The journal entry's detail: how it paired and what it may do.
    public var summary: String {
        let how =
            wasPreapproved
            ? "Paired with a link from the pair command, without confirming on a screen."
            : "Paired after confirming in Settings ▸ Paired Devices."
        return "\(device.model) · \(device.system). \(how) It can \(device.grants.abilities)."
    }
}
