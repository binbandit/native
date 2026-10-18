import Foundation

/// What opening a location in an app comes down to, worked out before anything runs, so the
/// catalog's launch rules can be checked (and recorded instead of run) without opening apps.
nonisolated enum OpenInRequest: Hashable, Sendable, CustomStringConvertible {
    /// Hands `item` (a folder, or a remote URL) to the app, like `open -a <app> <item>`.
    case open(URL, withApplication: URL)
    /// Starts a new instance of the app with these arguments.
    case launch(URL, arguments: [String])
    /// Runs a tool from the app's bundle with these arguments, then brings the app forward.
    case runTool(URL, arguments: [String], application: URL)
    /// Shows the folder in the file browser.
    case reveal(URL)

    init?(location: OpenInLocation, app: OpenInApp) {
        switch (location, app.target.launch) {
        case (.local(let folder), .document):
            self = .open(folder, withApplication: app.url)
        case (.local(let folder), .arguments(let arguments)):
            self = .launch(app.url, arguments: arguments + [folder.path(percentEncoded: false)])
        case (.local(let folder), .bundledTool(let path)):
            self = .runTool(
                app.url.appending(path: path), arguments: [folder.path(percentEncoded: false)], application: app.url)
        case (.local(let folder), .reveal):
            self = .reveal(folder)
        case (.remote(let host, let path), _):
            guard let url = app.target.remoteURL(host: host, path: path) else { return nil }
            self = .open(url, withApplication: app.url)
        }
    }

    var description: String {
        switch self {
        case .open(let item, let application): "open \(item.absoluteString) with \(application.lastPathComponent)"
        case .launch(let application, let arguments):
            "launch \(application.lastPathComponent) \(arguments.joined(separator: " "))"
        case .runTool(let tool, let arguments, _):
            "run \(tool.path(percentEncoded: false)) \(arguments.joined(separator: " "))"
        case .reveal(let folder): "reveal \(folder.path(percentEncoded: false))"
        }
    }
}
