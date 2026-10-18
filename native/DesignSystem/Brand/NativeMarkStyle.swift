/// Which edition of the emblem to draw, matching the app icon the user has in the Dock.
public enum NativeMarkStyle: Equatable, Sendable {
    /// One color, the current foreground style: the everyday mark.
    case standard
    /// The Beta icon's two tones: an amber link with a cream one (dark brown on light).
    case beta
    /// The Halloween icon's ghosts, in an edition's colors.
    case halloween(NativeHalloweenEdition)
}
