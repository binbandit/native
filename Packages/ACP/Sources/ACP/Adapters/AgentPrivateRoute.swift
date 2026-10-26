import Foundation

/// Operator-owned configuration. Credentials are references, never hydrated values.
public struct AgentPrivateRoute: Codable, Hashable, Sendable {
    public enum Authentication: Codable, Hashable, Sendable {
        case runtimeEnvironment(String)
        case nativeCredential(String)
    }

    public var identity: AgentRouteIdentity
    public var origin: String
    public var model: String
    public var authentication: Authentication
    public var proxyOrigin: String?
    public var bypassProxy: Bool
    public var customCAFile: String?

    public init(
        identity: AgentRouteIdentity, origin: String, model: String, authentication: Authentication,
        proxyOrigin: String? = nil, bypassProxy: Bool = false, customCAFile: String? = nil
    ) {
        self.identity = identity
        self.origin = origin
        self.model = model
        self.authentication = authentication
        self.proxyOrigin = proxyOrigin
        self.bypassProxy = bypassProxy
        self.customCAFile = customCAFile
    }

    public var requiredControls: Set<AgentNetworkCapabilities.Control> {
        var controls: Set<AgentNetworkCapabilities.Control> = [
            .providerOrigin, .model, .auxiliaryRoute, .mcpDisabled, .telemetryDisabled, .selfUpdateDisabled,
            .noFallback, .isolatedConfiguration,
        ]
        switch authentication {
        case .runtimeEnvironment: controls.insert(.runtimeCredential)
        case .nativeCredential: controls.insert(.nativeCredential)
        }
        if proxyOrigin != nil { controls.insert(.proxy) }
        if bypassProxy { controls.insert(.proxyBypass) }
        if customCAFile != nil { controls.insert(.customCA) }
        return controls
    }
}
