import Foundation
import NativeHostProtocol

// Plugins on this host, for every client: the catalog, its assets, and turning plugins on or off.
extension HostCore {
    /// The catalog as it is on disk now. Clients are told when it differs from what they last heard.
    func listPlugins() throws -> [HostPlugin] {
        let plugins = pluginCatalog.plugins(choices: try store.pluginChoices())
        if plugins != lastPublishedPlugins {
            lastPublishedPlugins = plugins
            for client in clients.values {
                client.notify(HostProtocol.Method.pluginsChanged, PluginsChangedNotification(plugins: plugins))
            }
        }
        return plugins
    }

    func pluginAsset(_ params: PluginAssetParams) throws -> PluginAsset {
        let data = try pluginCatalog.asset(pluginID: params.pluginID, path: params.path)
        let hash = ContentHash.sha256(data)
        return PluginAsset(hash: hash, size: data.count, data: params.knownHash == hash ? nil : data)
    }

    /// Only clients trusted with the host's setup may change it (`ClientGrants.managePlugins`).
    func setPluginEnabled(_ params: SetPluginEnabledParams, by client: ClientLink) throws -> [HostPlugin] {
        guard client.grants.managePlugins else { throw HostError.notAuthorized("turn plugins on or off") }
        guard pluginCatalog.plugins(choices: [:]).contains(where: { $0.id == params.pluginID }) else {
            throw PluginCatalog.Failure.unknownPlugin(params.pluginID)
        }
        try store.setPluginChoice(params.pluginID, enabled: params.isEnabled)
        return try listPlugins()
    }
}
