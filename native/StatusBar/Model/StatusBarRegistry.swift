import Foundation
import Observation

/// The items the status bar shows, and which ones the user hid (kept under `statusBar.hiddenItems`).
@Observable
final class StatusBarRegistry {
    private(set) var items: [AnyStatusBarItem] = []
    private(set) var hiddenIDs: Set<String> {
        didSet { defaults.set(hiddenIDs.sorted(), forKey: Self.hiddenKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let hiddenKey = "statusBar.hiddenItems"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenIDs = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    /// Adds an item, replacing one with the same id.
    func register(_ item: some StatusBarItem) {
        let item = AnyStatusBarItem(item)
        items.removeAll { $0.id == item.id }
        items.append(item)
    }

    func unregister(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// The items shown at one end, outer edge first.
    func visibleItems(_ placement: StatusBarPlacement) -> [AnyStatusBarItem] {
        items
            .filter { $0.placement == placement && !hiddenIDs.contains($0.id) }
            .sorted { $0.order < $1.order }
    }

    func isVisible(_ id: String) -> Bool {
        !hiddenIDs.contains(id)
    }

    func setVisible(_ visible: Bool, for id: String) {
        if visible {
            hiddenIDs.remove(id)
        } else {
            hiddenIDs.insert(id)
        }
    }
}
