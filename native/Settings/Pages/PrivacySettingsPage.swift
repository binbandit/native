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
                    id: PrivacySettingsPage.shareRow,
                    title: PrivacySettingsPage.sharingTitle(for: .shared),
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
            if telemetry.isNativeDestinationAvailable {
                SettingsRowGroup { shareRow }
            } else {
                SettingsNote(
                    Self.sharingTitle(for: telemetry),
                    systemImage: "hand.raised"
                ) {
                    Text("This version sends nothing to us. If a later one wants to, it will ask first.")
                }
                .settingsRevealTarget(Self.shareRow)
            }
            if !telemetry.organizationEndpoints.isEmpty {
                SettingsRowGroup { collectorRow }
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

    static func sharingTitle(for telemetry: TelemetryCenter) -> String {
        if telemetry.isNativeDestinationAvailable { return "Share anonymous usage with Native" }
        return telemetry.organizationEndpoints.isEmpty ? "This build sends nothing" : "Nothing is sent to Native"
    }

    private var shareRow: some View {
        SettingsRow(
            id: Self.shareRow,
            "Share anonymous usage with Native",
            description: Text("Helps decide what to build and fix next. Only what's listed below, never your work."),
            detail: Text(shareDetail)
        ) {
            SettingsSwitch(
                "Share anonymous usage with Native",
                isOn: Binding(get: { telemetry.isNativeEnabled }, set: { telemetry.setConsent($0) })
            )
        }
        .settingsManaged(by: .telemetryNative)
    }

    private var collectorRow: some View {
        SettingsRow(
            id: Self.collectorRow, "Your organization's collector",
            description: Text(
                telemetry.isNativeDestinationAvailable
                    ? "It receives the same anonymous events, whichever way the switch above is set."
                    : "It receives only the anonymous events listed below. Nothing is sent to Native."
            )
        ) {
            SettingsValue(hosts, monospaced: true)
        }
        .settingsManaged(by: .telemetryEndpoints)
    }

    /// Why the switch is where it is: the organization decided, or what off means.
    private var shareDetail: String {
        switch telemetry.nativeMode {
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
                ? "Nothing is sent to Native. Your organization's collector gets only this:"
                : "This build sends nothing. If a later one collects data, only this:"
        }
        return organization
            ? "Only while sharing is on, or to your organization's collector, and only this:"
            : "Only while sharing is on, and only this:"
    }

    private var logDescription: String {
        switch sentBatches {
        case nil: "Every batch sent from this Mac, exactly as it was sent."
        case 0: "Nothing has been sent from this Mac."
        case 1: "1 batch in the log, exactly as it was sent."
        case let count?: "The last \(count) batches sent from this Mac, newest first, exactly as they were sent."
        }
    }

    private var hosts: String {
        ListFormatter.localizedString(
            byJoining: telemetry.organizationEndpoints.map { $0.url.host() ?? $0.url.absoluteString })
    }
}

#if DEBUG
#Preview("Privacy settings") {
    DSPreviewPair {
        PrivacySettingsPage()
            .settingsPreviewPage()
    }
    .environment(TelemetryCenter.shared)
    .environment(PolicyCenter.shared)
}
#endif
