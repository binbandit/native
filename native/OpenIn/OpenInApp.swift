import AppKit

/// A catalog app that's installed, wherever LaunchServices found it (`/Applications`,
/// `~/Applications`, a JetBrains Toolbox folder…).
nonisolated struct OpenInApp: Identifiable, Hashable, Sendable {
    let target: OpenInTarget
    let url: URL
    /// The app's name as Finder shows it, e.g. "Visual Studio Code" or "Zed Preview".
    let name: String

    var id: OpenInTarget.ID { target.id }

    /// The installed catalog apps, in catalog order. Finder is always among them.
    static func installed(using workspace: NSWorkspace = .shared) -> [OpenInApp] {
        OpenInTarget.catalog.compactMap { target in
            let url = target.bundleIdentifiers.lazy.compactMap(workspace.urlForApplication(withBundleIdentifier:)).first
            guard let url else { return nil }
            // Finder keeps ".app" when the user shows all filename extensions.
            var name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            if name.hasSuffix(".app") {
                name.removeLast(4)
            }
            return OpenInApp(target: target, url: url, name: name)
        }
    }

    /// Opens `folder` in the app and brings it to the front.
    func open(_ folder: URL, using workspace: NSWorkspace = .shared) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        switch target.launch {
        case .document:
            try await workspace.open([folder], withApplicationAt: url, configuration: configuration)
        case .arguments(let arguments):
            // A running app ignores launch arguments, so these always start a new process.
            configuration.arguments = arguments + [folder.path(percentEncoded: false)]
            configuration.createsNewApplicationInstance = true
            try await workspace.openApplication(at: url, configuration: configuration)
        }
    }
}
