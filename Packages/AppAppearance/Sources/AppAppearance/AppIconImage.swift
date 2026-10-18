import Foundation

/// Where an app icon image comes from: compiled into the app's asset catalog, or a file a plugin
/// ships in its folder.
public enum AppIconImage: Hashable, Sendable {
    case asset(String)
    case file(URL)
}
