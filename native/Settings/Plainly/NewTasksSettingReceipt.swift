import Foundation

struct NewTasksSettingReceipt {
    struct Layer: Identifiable {
        var id: String { name }
        let name: String
        let symbol: String
        let value: String?
        var wins = false
        var overridden = false
        /// The organization's layer. Without a value it's left out, so an unmanaged Mac never
        /// reads as managed; when it decides, it carries a lock.
        var isOrganization = false
    }
    let title: String
    let context: String
    let value: String
    let source: SettingsSourceLabel.Source
    let layers: [Layer]
    let note: String
    var help: String?
    /// Why the result is what it is, beside it, when that isn't simply the winning layer's value.
    var reason: String?
    var isDefault = true
    var unavailable = false
    /// What happened to a saved choice the agent stopped offering, naming where it was saved.
    var unavailableNote: String?
    var modeOverrides = false
}
