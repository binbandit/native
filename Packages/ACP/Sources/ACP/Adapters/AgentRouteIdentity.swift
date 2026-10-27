import Foundation

/// Nonsecret identity sent by a client. It selects a host-owned route; it grants nothing.
public struct AgentRouteIdentity: Codable, Hashable, Sendable {
    public var routeID: String
    public var declarationID: String
    public var cliVersion: String
    public var adapterVersion: String

    public init(routeID: String, declarationID: String, cliVersion: String, adapterVersion: String) {
        self.routeID = routeID
        self.declarationID = declarationID
        self.cliVersion = cliVersion
        self.adapterVersion = adapterVersion
    }
}
