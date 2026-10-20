import NativeHostProtocol
import NativeLink
import NativePolicy
import SwiftUI

extension SettingsPane.ID {
    static let pairedDevices = Self("pairedDevices")
}

extension SettingsPane {
    /// Settings › Paired Devices: the iPhone companion and other devices that reach this Mac's host.
    static let pairedDevices = SettingsPane(
        id: .pairedDevices,
        title: "Paired Devices",
        systemImage: "iphone",
        group: .extensions,
        order: 40,
        keywords: ["iphone", "ipad", "companion", "phone", "pair", "qr", "remote", "mobile", "revoke"],
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: PairedDevicesSettingsPage.pairRow, title: "Pair iPhone",
                    description: "Scan a code with Native on your iPhone.", keywords: ["qr", "companion"]),
                SettingsSearchEntry(
                    id: PairedDevicesSettingsPage.enabledRow, title: "Allow paired devices to connect",
                    keywords: ["gateway", "network"]),
            ]
        },
        content: { PairedDevicesSettingsPage() }
    )
}

/// Pair an iPhone, see who's paired and when they were last here, rename them, change what they
/// may do, and remove them (with undo). Off until the first pairing: nothing listens before that.
struct PairedDevicesSettingsPage: View {
    static let pairRow = SettingsRowID("pairedDevices.pair")
    static let enabledRow = SettingsRowID("pairedDevices.enabled")

    @Environment(DurableHost.self) private var durableHost: DurableHost?
    @Environment(SettingsPresentation.self) private var settings
    @Environment(PolicyCenter.self) private var policyCenter: PolicyCenter?
    @State private var model = PairedDevicesModel()
    @State private var renaming: LinkDevice?
    @State private var newName = ""

    var body: some View {
        SettingsPage {
            SettingsHeader(
                title: "Paired Devices",
                description: Text(
                    "Follow tasks and answer agents from your iPhone. Devices reach this Mac's background host over an end-to-end encrypted connection, and only after you pair them here."
                )
            ) {
                if hostIsOn {
                    Button("Pair iPhone…") { model.beginPairing() }
                        .buttonStyle(.ds(.primary, size: .large))
                        .disabled(model.status == nil || !isAllowed)
                        .settingsRevealTarget(Self.pairRow)
                }
            }
            if !isAllowed {
                NoticeBanner(
                    tone: .info, systemImage: "building.2", title: "Your organization turned off paired devices",
                    detail:
                        "Devices can't pair with or connect to this Mac. Paired ones stay paired and reconnect if this changes."
                )
            }
            if !hostIsOn {
                NoticeBanner(
                    tone: .info, systemImage: "iphone.gen3",
                    title: "Paired devices connect through Native's background host",
                    detail: HostSessions.isEnabled
                        ? "It didn't start this time, so devices can't reach this Mac until it does. Settings ▸ Background says why."
                        : "It's off. Turn on \"Keep agents running when Native quits\" in Settings ▸ Background, so agents keep working while Native is closed and your iPhone can reach them."
                ) {
                    Button("Open Background Settings") { settings.open(.background) }
                        .buttonStyle(.ds(.primary, size: .medium))
                }
            } else if model.status == nil, let reason = model.unavailableReason {
                NoticeBanner(
                    tone: .warning, title: "Waiting for Native's background host",
                    detail: "\(reason) Native keeps trying.")
            }
            if let error = model.errorMessage {
                ErrorState("Couldn't change paired devices", suggestion: error)
            }
            if let status = model.status {
                Group {
                    gateway(status)
                    devices
                }
                .settingsManaged(by: .companionEnabled)
                .disabled(!isAllowed)
            }
        }
        .onAppear(perform: start)
        .onChange(of: hostIsOn) { start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: Binding(get: { model.isPairing }, set: { if !$0 { model.endPairing() } })) {
            PairPhoneSheet(model: model) { model.endPairing() }
        }
        .alert("Rename Device", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.rename(renaming, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only this Mac sees this name. The device keeps its own.")
        }
        .undoToast($model.undo)
    }

    private var hostIsOn: Bool { durableHost?.placement.usesHost ?? false }

    /// The organization's policy, as this app and the host read it.
    private var isAllowed: Bool {
        (policyCenter?.policy.companionEnabled ?? true) && model.status?.isAllowedByPolicy != false
    }

    private func start() {
        guard hostIsOn, let directory = durableHost?.location.directory else { return }
        model.start(hostDirectory: directory)
    }

    private func gateway(_ status: LinkStatus) -> some View {
        SettingsRowGroup {
            SettingsRow(
                id: Self.enabledRow,
                "Allow paired devices to connect",
                description: Text("Off keeps every pairing but closes the door until you turn it back on."),
                detail: Text(listenerLine(status))
            ) {
                SettingsSwitch(
                    "Allow paired devices to connect",
                    isOn: Binding(get: { status.isEnabled }, set: { model.setEnabled($0) }))
            }
        }
    }

    @ViewBuilder
    private var devices: some View {
        if model.activeDevices.isEmpty {
            EmptyStateView(
                "No paired devices", systemImage: "iphone",
                message: "Pair your iPhone to check on tasks, approve requests and send follow-ups away from this Mac."
            ) {
                Button("Pair iPhone…") { model.beginPairing() }
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.xxl)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SettingsSubheading("Devices")
                SettingsRowGroup {
                    ForEach(model.activeDevices) { entry in
                        deviceRow(entry)
                    }
                }
            }
        }
    }

    private func deviceRow(_ entry: LinkDeviceStatus) -> some View {
        let device = entry.device
        return SettingsRow(
            title: Text(device.name),
            icon: icon(for: device),
            description: Text(seenLine(entry)),
            detail: Text(grantsLine(device.grants))
        ) {
            if entry.isConnected {
                Badge("Connected", tone: .success)
            }
        } control: {
            Menu {
                Button("Rename…") {
                    newName = device.name
                    renaming = device
                }
                Toggle("Can Run Commands and Edit Files", isOn: grant(\.runCommands, of: device))
                Toggle("Can Install Updates", isOn: grant(\.manageHost, of: device))
                Toggle("Can Turn Plugins On and Off", isOn: grant(\.managePlugins, of: device))
                Divider()
                Button("Remove", role: .destructive) { model.revoke(device) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.ds(.ghost, size: .medium))
            .accessibilityLabel("Options for \(device.name)")
        }
    }

    /// One of the device's grants, changed on its own so the others stay as they are.
    private func grant(_ keyPath: WritableKeyPath<LinkGrants, Bool>, of device: LinkDevice) -> Binding<Bool> {
        Binding(
            get: { device.grants[keyPath: keyPath] },
            set: { isOn in
                var grants = device.grants
                grants[keyPath: keyPath] = isOn
                model.setGrants(grants, for: device)
            })
    }

    private func icon(for device: LinkDevice) -> String {
        if device.model.hasPrefix("Mac") { return "laptopcomputer" }
        return device.model.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone"
    }

    private func seenLine(_ entry: LinkDeviceStatus) -> String {
        let device = entry.device
        let paired = "Paired \(DSFormat.time(device.pairedAt, now: .now))"
        if entry.isConnected { return "\(device.model) · \(device.system) · Connected now · \(paired)" }
        guard let lastSeen = device.lastSeen else { return "\(device.model) · \(device.system) · \(paired)" }
        let age = DSFormat.compactAge(lastSeen, now: .now)
        let seen = age == "now" ? "Last seen just now" : "Last seen \(age) ago"
        return "\(device.model) · \(device.system) · \(seen) · \(paired)"
    }

    private func grantsLine(_ grants: LinkGrants) -> String {
        var abilities = ["Follows and drives tasks"]
        if grants.runCommands { abilities.append("runs commands and edits files") }
        if grants.manageHost { abilities.append("installs updates") }
        if grants.managePlugins { abilities.append("turns plugins on and off") }
        return abilities.joined(separator: ", ")
    }

    private func listenerLine(_ status: LinkStatus) -> String {
        switch status.listener.state {
        case .listening:
            let lan = status.addresses.first { $0.kind == .lan }.map { " at \($0.host)" } ?? ""
            return "Listening on port \(status.listener.port ?? 0)\(lan), and on Bonjour as “\(status.hostName)”."
        case .starting: return "Starting…"
        case .failed: return "Couldn't listen: \(status.listener.problem ?? "unknown error")"
        case .off, .unknown:
            return status.isEnabled
                ? "Not listening: pair a device to open the door." : "Off: nothing listens on the network."
        }
    }
}
