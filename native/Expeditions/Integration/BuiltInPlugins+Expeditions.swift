#if EXPEDITIONS_WIP
import Foundation

extension BuiltInPlugins {
    /// One instance for the app: the composition root connects its center, and the views read the
    /// same expeditions the plugin drives.
    static let expeditions = ExpeditionsPlugin()
}
#endif
