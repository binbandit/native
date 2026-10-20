import Foundation
import NativeHostProtocol

/// A host as the app addresses it: the id the host keeps in its own store, stable whatever network
/// path reaches it. The app target's older `HostID` (Project.host) predates paired hosts.
typealias RemoteHostID = NativeHostProtocol.HostID

/// Where a session runs and a project can have a checkout: this Mac, or a paired host
/// (`docs/durability.md`, "Host identity and many hosts").
nonisolated enum SessionDevice: Hashable, Codable, Sendable {
    /// This Mac: its own background host, or the app itself when no host runs.
    case thisMac
    case remote(RemoteHostID)

    var remoteHostID: RemoteHostID? {
        if case .remote(let id) = self { id } else { nil }
    }

    var isRemote: Bool {
        remoteHostID != nil
    }
}

/// Which host holds a remote session: `(HostID, HostSessionID)`. The app keys the session as it
/// keys every other one (`SessionKey`: agent and agent session id); this says where it lives.
nonisolated struct RemoteSessionRef: Hashable, Sendable {
    let host: RemoteHostID
    let session: HostSessionID
}

/// One row of the device picker in New Session: a device, whether it can take the session now, and
/// whether it has a checkout of the project or can get one.
struct SessionDeviceOption: Identifiable, Hashable {
    enum Availability: Hashable {
        case online
        /// Pairing or reconnecting; usable in a moment.
        case connecting
        /// Can't take a session now; `reason` says why and what fixes it.
        case offline(reason: String)
    }

    /// The project on that device.
    enum Checkout: Hashable {
        /// It has a checkout, in this folder.
        case present(path: String)
        /// It has none yet; starting a session there clones the project first.
        case willClone
        /// It has none and can't get one from here: "This project has no remote to clone from."
        case cannotClone(reason: String)
    }

    let device: SessionDevice
    /// "This Mac", or the host's name as the user calls it.
    let name: String
    let availability: Availability
    let checkout: Checkout

    var id: SessionDevice { device }

    init(device: SessionDevice, name: String, availability: Availability, checkout: Checkout) {
        self.device = device
        self.name = name
        self.availability = availability
        self.checkout = checkout
    }

    /// The shape before `checkout` had states, for previews written against it: no path reads as
    /// a device that can't get a checkout. Remove once nothing calls it.
    init(device: SessionDevice, name: String, availability: Availability, checkoutPath: String?) {
        self.init(
            device: device, name: name, availability: availability,
            checkout: checkoutPath.map { .present(path: $0) }
                ?? .cannotClone(reason: "No checkout of this project yet."))
    }

    /// The project's folder there, when it has one.
    var checkoutPath: String? {
        if case .present(let path) = checkout { path } else { nil }
    }

    var hasCheckout: Bool {
        checkoutPath != nil
    }

    /// Whether a session can start there right now, cloning the project first if it has to.
    var canStart: Bool {
        guard availability == .online else { return false }
        if case .cannotClone = checkout { return false }
        return true
    }

    /// Why the row is disabled, for its subtitle; nil when it isn't.
    var unavailableReason: String? {
        switch availability {
        case .online:
            if case .cannotClone(let reason) = checkout { reason } else { nil }
        case .connecting: "Connecting…"
        case .offline(let reason): reason
        }
    }
}
