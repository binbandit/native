import Foundation
import NativeHostProtocol

// Devices pairing with this host through its gateway (`docs/durability.md`, "Transport and security").
extension HostCore {
    /// Writes a new pairing into the activity journal and tells every client. Anyone running as
    /// this user can pair a device with `pair`, which nobody confirms on a screen, so each pairing
    /// leaves a trace the owner sees from any client.
    public func journalDevicePaired(_ name: String, detail: String) {
        let entry = ActivityEntry(id: 0, at: .now, sessionID: nil, kind: .devicePaired, subject: name, detail: detail)
        guard let stored = try? store.appendActivity(entry) else { return }
        for client in clients.values {
            client.notify(HostProtocol.Method.activity, stored)
        }
    }
}
