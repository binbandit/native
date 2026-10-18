import ACP
import Foundation
import NativeHostProtocol

/// The plugins installed on this host: a folder per plugin, each with a `plugin.json`
/// (`~/.native/plugins/<id>/` by default). The host reads only what it needs from a manifest (id,
/// name, version, whether it starts enabled); clients get the whole manifest.
struct PluginCatalog {
    enum Failure: Error, LocalizedError {
        case unknownPlugin(String)
        case pathOutsidePlugin(String)
        case missingAsset(String)
        case tooLarge(path: String, size: Int)

        var errorDescription: String? {
            switch self {
            case .unknownPlugin(let id): "No plugin named \(id) is installed on this host."
            case .pathOutsidePlugin(let path): "\(path) isn't inside the plugin's folder."
            case .missingAsset(let path): "The plugin has no file at \(path)."
            case .tooLarge(let path, let size):
                "\(path) is \(size) bytes; plugin assets are limited to \(PluginAsset.sizeLimit) bytes."
            }
        }
    }

    let directory: URL

    /// Every plugin with a readable manifest, sorted by id, enabled per the user's `choices` or else
    /// the manifest's `enabledByDefault` (on unless it says otherwise).
    func plugins(choices: [String: Bool]) -> [HostPlugin] {
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: "plugin.json")),
                let manifest = try? JSONDecoder().decode(JSONValue.self, from: data),
                let id = manifest["id"]?.stringValue
            else { return nil }
            var enabledByDefault = true
            if case .bool(let value)? = manifest["enabledByDefault"] { enabledByDefault = value }
            return HostPlugin(
                id: id, name: manifest["name"]?.stringValue ?? id, version: manifest["version"]?.stringValue,
                isEnabled: choices[id] ?? enabledByDefault, manifest: manifest)
        }
        .sorted { $0.id < $1.id }
    }

    /// Reads a file from a plugin's folder. The path is resolved (symbolic links included) and must
    /// stay inside the folder of the plugin whose manifest names `pluginID`.
    func asset(pluginID: String, path: String) throws -> Data {
        guard let folder = folder(of: pluginID) else { throw Failure.unknownPlugin(pluginID) }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        guard !path.hasPrefix("/") else { throw Failure.pathOutsidePlugin(path) }
        let file = folder.appending(path: path).resolvingSymlinksInPath().standardizedFileURL
        let resolved = file.path(percentEncoded: false)
        guard resolved.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { throw Failure.pathOutsidePlugin(path) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw Failure.missingAsset(path)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: resolved)[.size] as? Int) ?? 0
        guard size <= PluginAsset.sizeLimit else { throw Failure.tooLarge(path: path, size: size) }
        return try Data(contentsOf: file)
    }

    /// The folder whose manifest has this id. Folder names usually match ids, but the manifest is
    /// what counts.
    private func folder(of pluginID: String) -> URL? {
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders.first { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: "plugin.json")),
                let manifest = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return false }
            return manifest["id"]?.stringValue == pluginID
        }
    }
}
