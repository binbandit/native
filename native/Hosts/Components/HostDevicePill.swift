import NativeHostProtocol
import SwiftUI

/// The device picker's pill: the chosen device's glyph and name, and its state while it isn't
/// online. Opens `HostDevicePicker` in a popover.
struct HostDevicePill: View {
    let options: [SessionDeviceOption]
    let projectName: String
    @Binding var selection: SessionDevice
    @Binding var isPickerOpen: Bool
    /// The shortcut that opens the picker, as menus print it ("⇧⌘H"), for the tooltip.
    var shortcut: String?
    var onAddHost: (() -> Void)?
    /// Each device's look, when the caller knows more than its name (`HostDevicePicker.lookOf`).
    var lookOf: ((SessionDeviceOption) -> HostLook)?

    @Environment(\.hostLookStore) private var injectedLooks

    private var selected: SessionDeviceOption? {
        options.first { $0.device == selection }
    }

    var body: some View {
        let name = selected?.name ?? "This Mac"
        let availability = selected?.availability ?? .online
        Button {
            isPickerOpen.toggle()
        } label: {
            HStack(spacing: DS.Space.sm) {
                HostGlyph(
                    look: selected.flatMap { lookOf?($0) }
                        ?? (injectedLooks ?? .shared).look(for: selection, named: name),
                    size: HostsMetrics.rowGlyph, isDimmed: !availability.isOnline)
                Text(name)
                if !availability.isOnline {
                    HostAvailabilityMark(availability: availability)
                }
            }
        }
        .buttonStyle(.pill(isOpen: isPickerOpen))
        .help(
            shortcut.map { "Runs on \(name). Choose where it runs (\($0))" } ?? "Runs on \(name). Choose where it runs"
        )
        .accessibilityLabel("Run on")
        .accessibilityValue(availability.isOnline ? name : "\(name), \(availability.statusTitle)")
        .popover(isPresented: $isPickerOpen, arrowEdge: .top) {
            HostDevicePicker(
                options: options, projectName: projectName, selection: $selection, onAddHost: onAddHost,
                lookOf: lookOf
            ) {
                isPickerOpen = false
            }
            .dsPopoverBackground()
        }
    }
}

#if DEBUG
/// Devices in every state, for the components' previews and the fixture hosts.
enum HostDeviceFixtures {
    static let mini = RemoteHostID(UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
    static let studio = RemoteHostID(UUID(uuid: (3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)))
    static let buildBox = RemoteHostID(UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)))
    static let linux = RemoteHostID(UUID(uuid: (4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4)))

    static let options: [SessionDeviceOption] = [
        SessionDeviceOption(
            device: .thisMac, name: "This Mac", availability: .online,
            checkout: .present(path: "/Users/you/Developer/native")),
        SessionDeviceOption(
            device: .remote(mini), name: "Mac mini", availability: .online,
            checkout: .present(path: "/Users/you/code/native")),
        SessionDeviceOption(device: .remote(studio), name: "Studio", availability: .online, checkout: .willClone),
        SessionDeviceOption(
            device: .remote(buildBox), name: "build-box", availability: .connecting,
            checkout: .present(path: "/srv/native")),
        SessionDeviceOption(
            device: .remote(linux), name: "linux-01",
            availability: .offline(reason: "Not reachable. Nothing answered at 192.168.1.40 for 2 minutes."),
            checkout: .present(path: "/home/you/native")),
    ]
}

#Preview("Device picker") {
    @Previewable @State var selection = SessionDevice.remote(HostDeviceFixtures.mini)
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HostDevicePill(
                options: HostDeviceFixtures.options, projectName: "native", selection: $selection,
                isPickerOpen: .constant(false), shortcut: "⇧⌘H")
            HostDevicePicker(
                options: HostDeviceFixtures.options, projectName: "native", selection: $selection, onAddHost: {},
                dismiss: {}
            )
            .dsPopoverBackground()
        }
    }
}
#endif
