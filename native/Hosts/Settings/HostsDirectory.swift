#if NATIVE_HOSTSUI_WIP
import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

/// What Settings ▸ Hosts shows and does: This Mac and every paired host, and the user's actions on
/// them. The app's hosts (`AppHostsDirectory`) and the fixture hosts (`HostsFixtureDirectory`)
/// both provide it, so the page has one code path.
protocol HostsDirectory {
    /// This Mac first, then each paired host in the order they were paired.
    var hosts: [HostDisplay] { get }
    /// Reading or saving the pairings failed.
    var problem: String? { get }
    /// Whether Add Host can open here (the pairing flow is in this build).
    var canAddHost: Bool { get }

    func addHost()
    /// Names a paired host on this Mac; blank goes back to its machine name.
    func rename(_ host: RemoteHostID, to name: String)
    func setLook(_ look: HostLook, for device: SessionDevice)
    /// Forgets a paired host on this Mac. Its sessions keep running there. Returns what undoes it.
    func remove(_ host: RemoteHostID) -> (() -> Void)?
    /// Tries to connect now instead of at the next retry.
    func reconnect(_ host: RemoteHostID)
    /// Sets when a host keeps itself awake, so nobody opens Native on it to change it. Needs a
    /// pairing that may manage the host.
    func setKeepAwake(_ mode: KeepAwakeMode, on device: SessionDevice) async throws
    /// The device's connection, for checking its setup (`HostDoctorSheet`); nil when it can't be
    /// checked now.
    func doctorClient(for device: SessionDevice) -> NativeHostClient?
    /// Signs `agent` in on `device` with one of its methods; `apiKey` goes with an API key method.
    func signIn(
        _ agent: AgentDefinition.ID, on device: SessionDevice, with method: AuthMethod, apiKey: String?)
        async throws
    /// Forgets the key the host keeps for `method`.
    func removeAPIKey(_ agent: AgentDefinition.ID, on device: SessionDevice, for method: AuthMethod) async throws
    /// Ends a sign-in waiting at a link; the `signIn` call waiting on it then fails.
    func cancelSignIn(_ agent: AgentDefinition.ID, on device: SessionDevice) async
    /// Looks again whether `agent` is installed and signed in on `device`, after the user did either
    /// there themselves. Fails while the agent is working, with a message that says so.
    func checkAgain(_ agent: AgentDefinition.ID, on device: SessionDevice) async throws
}
#endif
