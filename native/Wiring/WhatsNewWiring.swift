import Foundation

extension AppModel {
    /// Whether a task or workflow waits on the user (a permission request, question or plan review),
    /// counted the way the Dock badge counts it. What's New never covers one.
    var hasWorkNeedingUser: Bool {
        DockBadgeWiring.count(model: self, workflows: BuiltInPlugins.automation.center.workflows, mode: .needsYou) > 0
    }
}
