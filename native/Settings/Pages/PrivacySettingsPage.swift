import NativePolicy
import NativeTelemetry
import SwiftUI

extension SettingsPane.ID {
    static let privacy = Self("privacy")
}

extension SettingsPane {
    static let privacy = SettingsPane(
        id: .privacy,
        title: "Privacy",
        systemImage: "hand.raised",
        group: .personal,
        order: 30,
        keywords: ["telemetry", "analytics", "usage", "crash", "data", "collector"],
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: PrivacySettingsPage.shareRow, title: "Share anonymous usage with Native",
                    keywords: ["telemetry", "opt in", "opt out"]),
                SettingsSearchEntry(id: PrivacySettingsPage.logRow, title: "Show what Native sends", keywords: ["log"]),
                SettingsSearchEntry(
                    id: PrivacySettingsPage.idRow, title: "Reset installation ID", keywords: ["identifier"]),
            ]
        },
        content: { PrivacySettingsPage() }
    )
}

/// What Native sends, to whom, and the switch for it. The copy is the promise: anything not listed
/// under "What's sent" never leaves the Mac through Native.
struct PrivacySettingsPage: View {
    static let shareRow = SettingsRowID("privacy.share")
    static let logRow = SettingsRowID("privacy.log")
    static let idRow = SettingsRowID("privacy.id")

    @Environment(TelemetryCenter.self) private var telemetry
    @State private var isShowingLog = false

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Privacy",
                description: Text(
                    "Your work stays yours. Prompts, transcripts, code and commands never leave this Mac through Native; agents talk to their own providers."
                ))
            SettingsRowGroup {
                shareRow
                if !telemetry.organizationEndpoints.isEmpty {
                    SettingsRow(
                        "Your organization's collector",
                        description: Text(
                            "The same anonymous events go to \(hosts), which your organization set up. Turning off Native's telemetry doesn't change this."
                        )
                    ) { EmptyView() }
                    .settingsManaged(by: .telemetryEndpoints)
                }
                SettingsRow(
                    "What's sent",
                    description: Text(
                        "Which features you use, how long Native takes to launch and when it stops responding, and which agents and versions start sessions. Each comes with a random ID for this installation, and the app and macOS versions."
                    )
                ) { EmptyView() }
                SettingsRow(
                    "What's never sent",
                    description: Text(
                        "Prompts, transcripts, file contents, file and folder names, commands, tool input and output, project and account names, or anything you type."
                    )
                ) { EmptyView() }
                SettingsRow(
                    id: Self.logRow, "What Native has sent",
                    description: Text("Every batch sent from this Mac, newest first, exactly as it was sent.")
                ) {
                    Button("Show What Native Sends") { isShowingLog = true }
                        .buttonStyle(.ds(.secondary, size: .medium))
                }
                SettingsRow(
                    id: Self.idRow, "Installation ID",
                    description: Text(telemetry.installationID.uuidString.lowercased())
                        .font(SettingsTextStyle.mono.font),
                    detail: Text(
                        "Random, and never linked to you. Resetting it makes this Mac look like a new installation.")
                ) {
                    Button("Reset ID") { telemetry.resetInstallationID() }
                        .buttonStyle(.ds(.secondary, size: .medium))
                }
            }
        }
        .sheet(isPresented: $isShowingLog) {
            TelemetrySentLogSheet(entries: telemetry.sentLog.entries().reversed())
        }
    }

    private var shareRow: some View {
        SettingsRow(
            id: Self.shareRow, "Share anonymous usage with Native",
            description: Text("Helps decide what to build and fix next."),
            detail: Text(shareDetail)
        ) {
            SettingsSwitch(
                "Share anonymous usage with Native",
                isOn: Binding(get: { telemetry.isNativeEnabled }, set: { telemetry.setConsent($0) }))
        }
        .settingsManaged(by: .telemetryNative)
        .settingsLocked(telemetry.isNativeDestinationAvailable ? nil : "Not collected yet")
    }

    private var shareDetail: String {
        guard telemetry.isNativeDestinationAvailable else {
            return "Native doesn't collect anything yet. If that changes, it will ask you first."
        }
        return switch telemetry.nativeMode {
        case .on: "Your organization has turned this on."
        case .off: "Your organization has turned this off."
        case .user: "When off, nothing is sent to Native, and nothing is kept to send later."
        }
    }

    private var hosts: String {
        ListFormatter.localizedString(
            byJoining: telemetry.organizationEndpoints.map { $0.url.host() ?? $0.url.absoluteString })
    }
}
