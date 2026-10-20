#if NATIVE_PREVIEWS_WIP
import Foundation
import SwiftUI

/// Agent icons for previews: the icons already cached are read, and a missing one is never fetched
/// (every request fails as if offline), so a preview stays off the network and writes nothing.
enum AgentIconPreviewFixtures {
    static let store = AgentIconStore(registry: AgentIconRegistry(session: offlineSession))

    /// The built-in agents' definitions, as their plugins declare them.
    static let agents: [AgentDefinition] = [
        BuiltInPlugins.claudeCode, BuiltInPlugins.codex, BuiltInPlugins.cursor, BuiltInPlugins.openCode,
        BuiltInPlugins.pi, BuiltInPlugins.copilot,
    ].flatMap { plugin in
        plugin.manifest.agents.map { AgentDefinition($0, pluginID: plugin.manifest.id) }
    }

    private static let offlineSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewOfflineURLProtocol.self]
        return URLSession(configuration: configuration)
    }()
}

/// Fails every request at once, the way being offline does.
private nonisolated final class PreviewOfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

extension View {
    /// Agent icons that stay off the network (`AgentIconPreviewFixtures.store`).
    func agentIconPreviewStore() -> some View {
        environment(\.agentIconStore, AgentIconPreviewFixtures.store)
    }
}
#endif
