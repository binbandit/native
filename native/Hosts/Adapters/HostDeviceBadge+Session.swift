import NativeLink
import SwiftUI

extension HostDeviceBadge {
    /// The badge for `session`, or nil when it runs on this Mac, which shows none:
    ///
    ///     if let badge = HostDeviceBadge(session: session.key, model: model) { badge }
    init?(session: SessionKey, model: AppModel, style: Style = .row, looks: HostLookStore = .shared) {
        guard case .remote(let id) = model.device(of: session) else { return nil }
        let host = model.hosts.host(id)
        let name = model.deviceName(.remote(id))
        self.init(
            name: name,
            look: looks.look(for: .remote(id), named: host?.paired.machineName ?? name),
            availability: host?.availability ?? .offline(reason: "It isn't paired with this Mac anymore."),
            style: style)
    }
}

extension HostDevicePill {
    /// The pill for a new session in `project`, with the devices the app knows. Show it while
    /// `model.offersRemoteHosts`; `selection` starts at `model.preferredDevice(for:)`.
    init(
        project: Project, model: AppModel, selection: Binding<SessionDevice>, isPickerOpen: Binding<Bool>,
        shortcut: String? = nil, onAddHost: (() -> Void)? = nil, looks: HostLookStore = .shared
    ) {
        self.init(
            options: model.deviceOptions(for: project.id), projectName: project.name, selection: selection,
            isPickerOpen: isPickerOpen, shortcut: shortcut, onAddHost: onAddHost
        ) { option in
            let machineName = option.device.remoteHostID.flatMap { model.hosts.host($0)?.paired.machineName }
            return looks.look(for: option.device, named: machineName ?? option.name)
        }
    }
}
