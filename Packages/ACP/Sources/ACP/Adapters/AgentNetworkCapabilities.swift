import Foundation

/// A plugin declaration, never evidence that the installed executable honors these controls.
/// Only the host's own qualified declaration can authorize a managed route.
public struct AgentNetworkCapabilities: Codable, Hashable, Sendable {
    public enum Control: String, Codable, Hashable, Sendable {
        case providerOrigin, model, runtimeCredential, nativeCredential, proxy, proxyBypass, customCA
        case auxiliaryRoute, mcpDisabled, telemetryDisabled, selfUpdateDisabled, noFallback, isolatedConfiguration
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var declarationID: String
    public var cliVersion: String
    public var adapterVersion: String
    public var controls: Set<Control>
    /// False until actual CLI/adapter fixture evidence is reviewed into the host's approval list.
    public var qualified: Bool

    public init(
        declarationID: String, cliVersion: String, adapterVersion: String,
        controls: Set<Control>, qualified: Bool = false
    ) {
        self.declarationID = declarationID
        self.cliVersion = cliVersion
        self.adapterVersion = adapterVersion
        self.controls = controls
        self.qualified = qualified
    }

    /// Candidate only. In particular, MCP precedence in adapter 2.2.2 is not qualified.
    public static let codexCandidate = Self(
        declarationID: "codex-responses-v1", cliVersion: "0.164.0", adapterVersion: "2.2.2",
        controls: [.providerOrigin, .model, .runtimeCredential])
}
