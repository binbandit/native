import Foundation

/// A catalog app that's installed, wherever the platform found it (on the Mac, LaunchServices:
/// `/Applications`, `~/Applications`, a JetBrains Toolbox folder…).
nonisolated struct OpenInApp: Identifiable, Hashable, Sendable {
    let target: OpenInTarget
    /// The installed app bundle.
    let url: URL
    /// The app's name as Finder shows it, e.g. "Visual Studio Code" or "Zed Preview".
    let name: String

    var id: OpenInTarget.ID { target.id }

    /// Whether the app can open the location: any local folder, and a remote one when the app can
    /// reach it from a URL. Terminals' `ssh` launches are recorded but not offered yet.
    func canOpen(_ location: OpenInLocation) -> Bool {
        OpenInRequest(location: location, app: self) != nil
    }
}
