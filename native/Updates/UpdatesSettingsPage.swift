import NativePolicy
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
                        id: UpdatesSettingsPage.whatsNewRow, title: "Show What's New",
                        keywords: ["highlights", "new features", "release notes"]),
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
    static let whatsNewRow = SettingsRowID("updates.whats-new")

    let controller: UpdateController

    @Environment(\.openURL) private var openURL
    @AppStorage(WhatsNewCenter.enabledKey) private var showsWhatsNew = true

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Updates",
                description: Text("Native updates itself from its releases on GitHub, verified before it installs.")
            )
            UpdateStatusView(controller: controller)
            SettingsRowGroup {
                versionRow
                channelRow
                SettingsRow(
                    id: Self.checksRow,
                    "Check for updates automatically",
                    description: Text("Look for a new version once a day.")
                ) {
                    SettingsSwitch(
                        "Check for updates automatically",
                        isOn: Binding(get: { controller.automaticallyChecks }, set: controller.setAutomaticallyChecks)
                    )
                    .disabled(!controller.isAvailable)
                }
                .settingsManaged(by: .updatesEnabled)
                SettingsRow(
                    id: Self.downloadsRow,
                    "Download updates automatically",
                    description: Text("Download updates in the background, so restarting is all it takes."),
                    detail: controller.automaticallyChecks ? nil : Text("Turn on automatic checks to use this.")
                ) {
                    SettingsSwitch(
                        "Download updates automatically",
                        isOn: Binding(
                            get: { controller.automaticallyDownloads }, set: controller.setAutomaticallyDownloads)
                    )
                    .disabled(!controller.isAvailable || !controller.automaticallyChecks)
                }
                .settingsManaged(by: .updatesEnabled)
                SettingsRow(
                    id: Self.whatsNewRow,
                    "Show What's New",
                    description: Text(
                        "After an update, show its highlights once. Help ▸ What's New shows them any time.")
                ) {
                    SettingsSwitch("Show What's New", isOn: $showsWhatsNew)
                }
            }
        }
    }

    private var versionRow: some View {
        SettingsRow(id: Self.versionRow, "Version") {
            HStack(spacing: DS.Space.lg) {
                SettingsValue("\(controller.current.channel.displayName) \(controller.current.displayVersion)")
                if let url = controller.current.releaseNotesURL {
                    Button("Release Notes") { openURL(url) }
                }
            }
        }
    }

    @ViewBuilder
    private var channelRow: some View {
        if controller.channels.count > 1 {
            SettingsRow(
                id: Self.channelRow,
                "Update channel",
                description: Text(controller.channel.summary),
                detail: controller.channel == .beta
                    ? Text("Going back to Stable keeps this beta until a newer stable release arrives.") : nil
            ) {
                SettingsSelect(
                    label: "Update channel",
                    selection: Binding(get: { controller.channel }, set: controller.setChannel),
                    options: controller.channels.map { .init(value: $0, title: $0.title) }
                )
                .disabled(!controller.isAvailable)
            }
            .settingsManaged(by: .updatesChannels)
        } else {
            SettingsRow(
                id: Self.channelRow,
                "Update channel",
                description: Text(controller.channel.summary),
                detail: Text(
                    controller.current.channel.isNightly
                        ? "Native Nightly always follows nightly builds. Install Native for stable releases; the two live side by side."
                        : "Your organization chose this channel."
                )
            ) {
                SettingsValue(controller.channel.title)
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Updates settings") {
    DSPreviewPair {
        UpdatesSettingsPage(controller: .preview("available"))
            .settingsPreviewPage()
    }
}

#Preview("Updates settings - Development build") {
    DSPreviewPair {
        UpdatesSettingsPage(controller: .preview("developmentBuild"))
            .settingsPreviewPage()
    }
}
#endif
