import SwiftUI

extension SettingsPane.ID {
    static let updates = Self("updates")
}

extension SettingsPane {
    /// Settings ▸ Updates, listed in `AppSettingsPanes`. It reads the app's `UpdateController` from
    /// the environment.
    static let updates =
        SettingsPane(
            id: .updates,
            title: "Updates",
            systemImage: "arrow.down.circle",
            group: .more,
            order: 10,
            keywords: ["update", "version", "beta", "nightly", "sparkle", "release notes", "upgrade"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: UpdatesSettingsPage.channelRow, title: "Update channel",
                        keywords: ["beta", "stable", "nightly"]),
                    SettingsSearchEntry(id: UpdatesSettingsPage.checksRow, title: "Check for updates automatically"),
                    SettingsSearchEntry(id: UpdatesSettingsPage.downloadsRow, title: "Download updates automatically"),
                    SettingsSearchEntry(
                        id: UpdatesSettingsPage.versionRow, title: "Version", keywords: ["build", "release notes"]),
                ]
            },
            content: { UpdatesSettingsEntry() }
        )
}

/// Finds the app's `UpdateController`, which `NativeApp` puts in the environment.
private struct UpdatesSettingsEntry: View {
    @Environment(UpdateController.self) private var controller: UpdateController?

    var body: some View {
        if let controller {
            UpdatesSettingsPage(controller: controller)
        } else {
            SettingsPage {
                SettingsHeader("Updates", description: Text("The updater isn't running in this window."))
            }
        }
    }
}

struct UpdatesSettingsPage: View {
    static let channelRow = SettingsRowID("updates.channel")
    static let checksRow = SettingsRowID("updates.automatic-checks")
    static let downloadsRow = SettingsRowID("updates.automatic-downloads")
    static let versionRow = SettingsRowID("updates.version")

    let controller: UpdateController

    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Updates",
                description: Text("Native updates itself from its releases on GitHub, verified before it installs.")
            )
            Card {
                UpdateStatusView(controller: controller)
            }
            SettingsRowGroup {
                versionRow
                channelRow
                SettingsRow(
                    id: Self.checksRow,
                    "Check automatically",
                    description: Text("Look for a new version once a day.")
                ) {
                    SettingsSwitch(
                        "Check automatically",
                        isOn: Binding(get: { controller.automaticallyChecks }, set: controller.setAutomaticallyChecks)
                    )
                    .disabled(!controller.isAvailable)
                }
                SettingsRow(
                    id: Self.downloadsRow,
                    "Download automatically",
                    description: Text("Download updates in the background, so restarting is all it takes."),
                    detail: controller.automaticallyChecks ? nil : Text("Turn on automatic checks to use this.")
                ) {
                    SettingsSwitch(
                        "Download automatically",
                        isOn: Binding(
                            get: { controller.automaticallyDownloads }, set: controller.setAutomaticallyDownloads)
                    )
                    .disabled(!controller.isAvailable || !controller.automaticallyChecks)
                }
            }
        }
    }

    private var versionRow: some View {
        SettingsRow(
            id: Self.versionRow,
            "Version",
            description: Text("\(controller.current.channel.displayName) \(controller.current.displayVersion)")
        ) {
            if let url = controller.current.releaseNotesURL {
                Button("Release Notes") { openURL(url) }
                    .buttonStyle(.ds(.secondary))
            }
        }
    }

    @ViewBuilder
    private var channelRow: some View {
        if controller.channels.count > 1 {
            SettingsRow(
                id: Self.channelRow,
                "Channel",
                description: Text(controller.channel.summary),
                detail: controller.channel == .beta
                    ? Text("Going back to Stable keeps this beta until a newer stable release arrives.") : nil
            ) {
                SettingsSelect(
                    label: "Channel",
                    selection: Binding(get: { controller.channel }, set: controller.setChannel),
                    options: controller.channels.map { .init(value: $0, title: $0.title) }
                )
                .disabled(!controller.isAvailable)
            }
        } else {
            SettingsRow(
                id: Self.channelRow,
                "Channel",
                description: Text(controller.channel.summary),
                detail: Text(
                    "Native Nightly always follows nightly builds. Install Native for stable releases; the two live side by side."
                )
            ) {
                Text(controller.channel.title)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
        }
    }
}
