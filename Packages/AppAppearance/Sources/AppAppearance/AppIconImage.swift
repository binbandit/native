import Foundation

/// Where an app icon image comes from: compiled into the app's asset catalog, or a file a plugin
/// ships in its folder.
public enum AppIconImage: Hashable, Sendable {
    case asset(String)
    case file(URL)
}

/// One icon in both appearances.
public struct AppIconImagePair: Hashable, Sendable {
    public let light: AppIconImage
    public let dark: AppIconImage

    public init(light: AppIconImage, dark: AppIconImage) {
        self.light = light
        self.dark = dark
    }

    public func image(isDark: Bool) -> AppIconImage {
        isDark ? dark : light
    }
}
