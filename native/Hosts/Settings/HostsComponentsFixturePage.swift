#if NATIVE_HOSTSUI_WIP
#if DEBUG
import SwiftUI

/// The device picker, its pill and the device badges on fixture devices, in place of Settings ▸
/// Hosts with `-NativeHostsFixtures components`: a way to check their real rendering before they're
/// wired into New Session, the sidebar and the session header. Development builds only.
struct HostsComponentsFixturePage: View {
    @State private var selection = SessionDevice.remote(HostDeviceFixtures.mini)
    @State private var isPickerOpen = false

    private let looks: [SessionDevice: HostLook] = [
        .remote(HostDeviceFixtures.mini): HostLook(symbol: .mini, tint: .cobalt),
        .remote(HostDeviceFixtures.studio): HostLook(symbol: .studio, tint: .prism),
        .remote(HostDeviceFixtures.buildBox): HostLook(symbol: .server, tint: .fern),
        .remote(HostDeviceFixtures.linux): HostLook(symbol: .pc, tint: .ember),
    ]

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Device picker and badges", description: Text("Fixture devices, for checking the components."))
            HStack(alignment: .top, spacing: DS.Space.xxxl) {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    SettingsSubheading("New Session")
                    HostDevicePill(
                        options: HostDeviceFixtures.options, projectName: "native", selection: $selection,
                        isPickerOpen: $isPickerOpen, shortcut: "⇧⌘H", onAddHost: {}, lookOf: look)
                    HostDevicePicker(
                        options: HostDeviceFixtures.options, projectName: "native", selection: $selection,
                        onAddHost: {}, lookOf: look, dismiss: {}
                    )
                    .background(.dsOverlay, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(.dsSeparator, lineWidth: 1)
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    SettingsSubheading("Sidebar rows")
                    VStack(spacing: DS.Space.xs) {
                        ForEach(rows, id: \.title) { row in
                            TaskRow(
                                title: row.title, status: row.status, date: .now.addingTimeInterval(row.age),
                                accessory: badge(row.option, style: .row), action: {})
                        }
                    }
                    .frame(width: DS.Size.sidebarWidth)
                    SettingsSubheading("Session header")
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        ForEach(HostDeviceFixtures.options.dropFirst()) { option in
                            badge(option, style: .header)
                        }
                    }
                }
            }
        }
    }

    private struct Row {
        let title: String
        let status: TaskStatus
        let age: TimeInterval
        let option: SessionDeviceOption
    }

    private var rows: [Row] {
        let options = HostDeviceFixtures.options
        return [
            Row(title: "Migrate the billing webhooks", status: .working, age: -60, option: options[1]),
            Row(title: "Nightly dependency bumps", status: .idle, age: -7200, option: options[3]),
            Row(title: "Profile the indexer", status: .needsInput, age: -600, option: options[4]),
            Row(title: "Fix the flaky upload test", status: .done, age: -86_400, option: options[2]),
        ]
    }

    private func look(_ option: SessionDeviceOption) -> HostLook {
        looks[option.device] ?? .thisMac(machineName: "MacBook Pro")
    }

    private func badge(_ option: SessionDeviceOption, style: HostDeviceBadge.Style) -> HostDeviceBadge {
        HostDeviceBadge(name: option.name, look: look(option), availability: option.availability, style: style)
    }
}
#endif
#endif
