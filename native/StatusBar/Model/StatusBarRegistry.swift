import Foundation
import Observation

/// The items the status bar shows. Each item is shown or hidden by default when it's registered;
/// the user's own choices override that and are kept under `statusBar.visibility`.
@Observable
final class StatusBarRegistry {
    private(set) var items: [AnyStatusBarItem] = []
    /// The user's choices, by item id. Items without one use their default.
    private var choices: [String: Bool] {
        didSet { defaults.set(choices, forKey: Self.visibilityKey) }
    }

    private var defaultVisibility: [String: Bool] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    private static let visibilityKey = "statusBar.visibility"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choices = defaults.dictionary(forKey: Self.visibilityKey) as? [String: Bool] ?? [:]
    }

    /// Adds an item, replacing one with the same id. Native keeps the bar minimal: register only
    /// what most people want as visible by default, and let the rest be turned on from the bar's
    /// menu.
    func register(_ item: some StatusBarItem, isVisibleByDefault: Bool = true) {
        let item = AnyStatusBarItem(item)
        items.removeAll { $0.id == item.id }
        items.append(item)
        defaultVisibility[item.id] = isVisibleByDefault
    }

    func unregister(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// The items shown at one end, outer edge first.
    func visibleItems(_ placement: StatusBarPlacement) -> [AnyStatusBarItem] {
        items
            .filter { $0.placement == placement && isVisible($0.id) }
            .sorted { $0.order < $1.order }
    }

    /// Every item, hidden ones included, in the order the bar shows them: leading, then trailing.
    var orderedItems: [AnyStatusBarItem] {
        items.sorted { ($0.placement == .leading ? 0 : 1, $0.order) < ($1.placement == .leading ? 0 : 1, $1.order) }
    }

    func isVisible(_ id: String) -> Bool {
        choices[id] ?? defaultVisibility[id] ?? true
    }

    func setVisible(_ visible: Bool, for id: String) {
        choices[id] = visible
    }
}
