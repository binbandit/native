import NativeHostProtocol
import NativeLink
import SwiftUI

/// One host: how it's connected (with the log), its Native version and updates, its plugins, what
/// this phone calls it, and unpairing.
struct HostDetailView: View {
    let host: HostConnection

    @Environment(CompanionStore.self) private var store
    @Environment(AppIconController.self) private var icons
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingUnpair = false

    var body: some View {
        @Bindable var host = host
        List {
            Section {
                HStack(spacing: DS.Space.lg) {
                    HostMark(preferences: host.preferences)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(host.name).font(CompanionType.headline).foregroundStyle(.dsTextPrimary)
                        HostConnectionLine(host: host)
                    }
                }
                if let detail = host.phase.detail(hostName: host.name) {
                    Text(detail).font(CompanionType.subheadline).foregroundStyle(.dsTextSecondary)
                }
                if case .pairingEnded = host.phase {
                    Button("Pair Again") { store.isAddingHost = true }
                    // Revoking on the Mac can be undone there; then this simply connects again.
                    Button("Try Again") { host.reconnect() }
                } else if !host.phase.isConnected {
                    Button("Retry Now") { host.reconnect() }
                }
                NavigationLink("Connection Log") { ConnectionLogView(host: host) }
            }
            HostUpdateSection(host: host)
            Section {
                NavigationLink {
                    PluginCatalogView(host: host)
                } label: {
                    LabeledContent(
                        "Plugins", value: "\(host.plugins.filter(\.isEnabled).count) of \(host.plugins.count) on")
                }
            }
            Section {
                TextField(
                    host.host.machineName,
                    text: Binding(
                        get: { host.preferences.label ?? "" }, set: { host.preferences.label = $0.isEmpty ? nil : $0 })
                )
                .accessibilityIdentifier("hostLabel")
                HostThemePicker(themeID: $host.preferences.themeID)
                Picker("Symbol", selection: $host.preferences.symbol) {
                    ForEach(HostPreferences.symbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
            } header: {
                Text("On This Phone")
            } footer: {
                Text(
                    "Only this phone sees the name, color and symbol. \(host.host.machineName) is the machine's own name."
                )
            }
            Section {
                Picker("App Icon While Connected", selection: $host.preferences.appIcon) {
                    Label {
                        Text("Don't Change")
                    } icon: {
                        AppIconThumbnail(name: icons.theme.iconName, size: CompanionMetrics.hostMarkSmall)
                    }
                    .tag(CompanionAppIcon?.none)
                    ForEach(CompanionAppIcon.allCases) { theme in
                        Label {
                            Text(theme.title)
                        } icon: {
                            AppIconThumbnail(name: theme.iconName, size: CompanionMetrics.hostMarkSmall)
                        }
                        .tag(Optional(theme))
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: host.preferences.appIcon) { icons.applyNow() }
                .accessibilityIdentifier("hostAppIcon")
            } footer: {
                Text(
                    "Shows while \(host.name) is the host you're looking at. iOS shows an alert each time the icon changes, and a celebration's icon wins while it lasts."
                )
            }
            Section("Notifications") {
                Toggle("Updates", isOn: $host.preferences.notifiesAboutUpdates)
                Toggle("Approvals", isOn: $host.preferences.notifiesAboutApprovals)
                Text(
                    "Approval alerts while the app is closed need push notifications, which arrive with a later version."
                )
                .font(CompanionType.caption).foregroundStyle(.dsTextTertiary)
            }
            Section {
                LabeledContent("Machine", value: host.host.machineName)
                if case .connected(let info) = host.phase {
                    LabeledContent("Native", value: "\(info.hostInfo.version) (\(info.hostInfo.build))")
                }
                LabeledContent("Key", value: host.host.hostKey.fingerprint)
                LabeledContent("Paired", value: host.host.pairedAt.formatted(date: .abbreviated, time: .shortened))
                Button("Unpair", role: .destructive) { isConfirmingUnpair = true }
            } footer: {
                Text(
                    "Unpairing forgets this host's key on this phone. Remove the phone on the Mac too (Settings › Paired Devices)."
                )
            }
        }
        .font(CompanionType.body)
        .scrollContentBackground(.hidden)
        .background(.dsBackground)
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .hostTint(host.preferences)
        .confirmationDialog("Unpair \(host.name)?", isPresented: $isConfirmingUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) {
                store.unpair(host)
                dismiss()
            }
        } message: {
            Text("This phone forgets its key for \(host.name). To reconnect, pair again from the Mac.")
        }
    }
}

/// Every connection attempt and its outcome, for when something's genuinely wrong.
struct ConnectionLogView: View {
    let host: HostConnection

    var body: some View {
        List(host.log.reversed()) { entry in
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Label(entry.message, systemImage: symbol(entry.kind))
                    .font(CompanionType.subheadline)
                    .foregroundStyle(entry.kind == .failure ? .dsDanger : .dsTextPrimary)
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(CompanionType.caption).foregroundStyle(.dsTextTertiary)
            }
        }
        .overlay {
            if host.log.isEmpty {
                EmptyStateView(
                    "Nothing logged yet", systemImage: "list.bullet.rectangle",
                    message: "Connection attempts to \(host.name) show here.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(.dsBackground)
        .navigationTitle("Connection Log")
        .toolbar {
            ShareLink(
                item: host.log.map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.message)" }.joined(
                    separator: "\n"))
        }
    }

    private func symbol(_ kind: LinkLogEntry.Kind) -> String {
        switch kind {
        case .attempt: "arrow.right.circle"
        case .success: "checkmark.circle"
        case .failure: "xmark.circle"
        case .info: "info.circle"
        }
    }
}
