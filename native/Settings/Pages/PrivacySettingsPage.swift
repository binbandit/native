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
                SettingsSearchEntry(
                    id: PrivacySettingsPage.disclosureRow, title: "What Native sends",
                    keywords: ["never sent", "prompts", "crash reports"]),
                SettingsSearchEntry(id: PrivacySettingsPage.logRow, title: "What Native has sent", keywords: ["log"]),
                SettingsSearchEntry(
                    id: PrivacySettingsPage.idRow, title: "Reset installation ID", keywords: ["identifier"]),
            ]
        },
        content: { PrivacySettingsPage() }
    )
}

/// The switch for Native's telemetry, exactly what it carries and what it never does, and the log
/// and ID to check it by. The copy is the promise: anything not listed as sent never leaves the Mac
/// through Native.
struct PrivacySettingsPage: View {
    static let shareRow = SettingsRowID("privacy.share")
    static let collectorRow = SettingsRowID("privacy.collector")
    static let disclosureRow = SettingsRowID("privacy.disclosure")
    static let logRow = SettingsRowID("privacy.log")
    static let idRow = SettingsRowID("privacy.id")

    @Environment(TelemetryCenter.self) private var telemetry
    @State private var isShowingLog = false
    /// Batches in the sent log, read when the page opens.
    @State private var sentBatches: Int?

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Privacy",
                description: Text(
                    "Your work stays yours. Prompts, transcripts, code and commands never leave this Mac through Native. Each agent sends your work only to its own provider."
                ))
            SettingsRowGroup {
                shareRow
                if !telemetry.organizationEndpoints.isEmpty {
                    collectorRow
                }
            }
            PrivacyDisclosure(scope: disclosureScope)
                .settingsRevealTarget(Self.disclosureRow)
            SettingsSubheading("On this Mac")
            SettingsRowGroup {
                SettingsRow(id: Self.logRow, "What Native has sent", description: Text(logDescription)) {
                    Button("Show Log") { isShowingLog = true }
                        .buttonStyle(.settings)
                }
                SettingsRow(
                    id: Self.idRow, "Installation ID",
                    description: Text(
                        "Random, and never linked to you. Resetting it makes this Mac look like a new installation.")
                ) {
                    HStack(spacing: DS.Space.lg) {
                        SettingsValue(telemetry.installationID.uuidString.lowercased(), monospaced: true)
                        Button("Reset") { telemetry.resetInstallationID() }
                            .buttonStyle(.settings)
                            .accessibilityLabel("Reset Installation ID")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingLog) {
            TelemetrySentLogSheet(entries: telemetry.sentLog.entries().reversed())
        }
        .task(id: isShowingLog) {
            sentBatches = telemetry.sentLog.entries().count
        }
    }

    private var shareRow: some View {
        SettingsRow(
            id: Self.shareRow,
            title: Text("Share anonymous usage with Native"),
            description: Text("Helps decide what to build and fix next. Only what's listed below, never your work."),
            detail: Text(shareDetail)
        ) {
            if !telemetry.isNativeDestinationAvailable {
                SettingsBadge("Not collected yet")
            }
        } control: {
            SettingsSwitch(
                "Share anonymous usage with Native",
                isOn: Binding(get: { telemetry.isNativeEnabled }, set: { telemetry.setConsent($0) })
            )
            .disabled(!telemetry.isNativeDestinationAvailable)
        }
        .settingsManaged(by: .telemetryNative)
    }

    private var collectorRow: some View {
        SettingsRow(
            id: Self.collectorRow, "Your organization's collector",
            description: Text("It receives the same anonymous events, whichever way the switch above is set.")
        ) {
            SettingsValue(hosts, monospaced: true)
        }
        .settingsManaged(by: .telemetryEndpoints)
    }

    /// Why the switch is where it is: nothing to send yet, the organization decided, or what off means.
    private var shareDetail: String {
        guard telemetry.isNativeDestinationAvailable else {
            return "This version of Native doesn't collect anything. If a later one does, it will ask you first."
        }
        return switch telemetry.nativeMode {
        case .on: "Your organization has turned this on."
        case .off: "Your organization has turned this off."
        case .user: "When off, nothing is sent to Native, and nothing is kept to send later."
        }
    }

    /// When the list applies, so the note never promises more or less than the switches do.
    private var disclosureScope: String {
        let organization = !telemetry.organizationEndpoints.isEmpty
        guard telemetry.isNativeDestinationAvailable else {
            return organization
                ? "Native collects nothing yet. Your organization's collector gets only this:"
                : "Native collects nothing yet. If it ever does, only this:"
        }
        return organization
            ? "Only while sharing is on, or to your organization's collector, and only this:"
            : "Only while sharing is on, and only this:"
    }

    private var logDescription: String {
        switch sentBatches {
        case nil: "Every batch sent from this Mac, exactly as it was sent."
        case 0: "Nothing has been sent from this Mac."
        case 1: "1 batch sent from this Mac, kept exactly as it was sent."
        case let count?: "\(count) batches sent from this Mac, kept exactly as they were sent."
        }
    }

    private var hosts: String {
        ListFormatter.localizedString(
            byJoining: telemetry.organizationEndpoints.map { $0.url.host() ?? $0.url.absoluteString })
    }
}
