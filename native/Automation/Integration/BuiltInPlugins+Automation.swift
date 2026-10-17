import Foundation
import NativeAutomation

extension BuiltInPlugins {
    /// One instance for the app: the composition root gives its center a host, and the views read
    /// the same goals and runs the plugin drives.
    static let automation = AutomationPlugin()
}
