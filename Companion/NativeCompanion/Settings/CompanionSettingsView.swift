import NativeHostProtocol
import SwiftUI

/// Settings: the paired hosts (and adding one), appearance, the app icon and celebrations,
/// notifications.
struct CompanionSettingsView: View {
    @Environment(CompanionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CompanionAppearance.key) private var appearance = CompanionAppearance.system
    @Environment(AppIconController.self) private var icons
    @State private var notificationsAllowed: Bool?

    var body: some View {
        NavigationStack {
            List {
                Section("Hosts") {
                    ForEach(store.hosts) { host in
                        NavigationLink {
                            HostDetailView(host: host)
                        } label: {
                            HStack(spacing: DS.Space.lg) {
                                HostMark(preferences: host.preferences, size: CompanionMetrics.hostMarkSmall)
                                VStack(alignment: .leading) {
                                    Text(host.name)
                                    HostConnectionLine(host: host)
                                }
                            }
                        }
                    }
                    Button("Add Host", systemImage: "plus") {
                        dismiss()
                        store.isAddingHost = true
                    }
                    .accessibilityIdentifier("addHost")
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(CompanionAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    NavigationLink {
                        AppIconSettingsView()
                    } label: {
                        HStack(spacing: DS.Space.lg) {
                            AppIconThumbnail(name: icons.target().name)
                            Text("App Icon")
                        }
                    }
                    .accessibilityIdentifier("appIcon")
                }
                Section("Notifications") {
                    Button("Allow Notifications") {
                        Task { notificationsAllowed = await CompanionNotifications.requestAuthorization() }
                    }
                    if let notificationsAllowed {
                        Text(
                            notificationsAllowed
                                ? "Notifications are on." : "Notifications are off. Turn them on in the Settings app."
                        )
                        .font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: CompanionDevice.peerInfo.version)
                    LabeledContent("Host protocol", value: "\(HostProtocol.version)")
                }
            }
            .font(CompanionType.body)
            .scrollContentBackground(.hidden)
            .background(.dsBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
