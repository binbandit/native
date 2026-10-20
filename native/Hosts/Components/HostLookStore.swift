import Foundation
import Observation
import SwiftUI

/// The look the user picked for each device, kept on this Mac by device. A removed host keeps its
/// entry, so undoing the removal or pairing the same host again brings its look back.
@Observable
final class HostLookStore {
    static let shared = HostLookStore()

    private var looks: [SessionDevice: HostLook]
    @ObservationIgnored private let defaults: UserDefaults

    private static let defaultsKey = "hostLooks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.defaultsKey).flatMap {
            try? JSONDecoder().decode([Entry].self, from: $0)
        }
        looks = Dictionary((saved ?? []).map { ($0.device, $0.look) }, uniquingKeysWith: { _, last in last })
    }

    /// The look the user picked for `device`, else the one it has until they do; `name` is what the
    /// device is called.
    func look(for device: SessionDevice, named name: String) -> HostLook {
        looks[device] ?? .fallback(for: device, named: name)
    }

    func setLook(_ look: HostLook, for device: SessionDevice) {
        guard looks[device] != look else { return }
        looks[device] = look
        let entries = looks.map { Entry(device: $0.key, look: $0.value) }
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.defaultsKey)
    }

    /// One saved look. A list rather than a dictionary, since `SessionDevice` isn't a string key.
    private struct Entry: Codable {
        let device: SessionDevice
        let look: HostLook
    }
}

extension EnvironmentValues {
    /// A store other than `HostLookStore.shared`, for previews and fixtures.
    @Entry var hostLookStore: HostLookStore?
}
