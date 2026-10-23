import NativeCommands
import NativeHostClient
import NativeHostProtocol
import SwiftUI

#if os(macOS)
import ServiceManagement
#endif

extension SettingsPane.ID {
    static let background = Self("background")
}

extension SettingsPane {
    /// Settings › Background: whether agents keep running when Native quits, and how the background
    /// host is doing (`docs/durability.md`).
    static let background = SettingsPane(
        id: .background,
        title: "Background",
        systemImage: "moon.zzz",
        group: .agents,
        order: 10,
        keywords: ["durable", "quit", "keep running", "host", "login items", "background items", "launchd"],
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: BackgroundSettingsPage.keepRunningRow, title: "Keep agents running when Native quits",
                    description: "Agents finish their work in Native's background host after you quit.",
                    keywords: ["durable", "quit", "background", "host"], plainly: .keepRunning),
                SettingsSearchEntry(
                    id: BackgroundSettingsPage.hostRow, title: "Background host",
                    keywords: ["restart", "status", "login items"], plainly: .backgroundHelper),
                SettingsSearchEntry(
                    id: BackgroundSettingsPage.checkRow, title: "Check this Mac",
                    keywords: ["doctor", "droid", "mac mini", "health", "diagnose"]),
            ]
        },
        content: { BackgroundSettingsPage() }
    )
}

/// The one durability setting and the host's state. The setting applies from the next launch,
/// since a running task can't move between the app and the host; the page offers the relaunch.
struct BackgroundSettingsPage: View {
    static let keepRunningRow = SettingsRowID("background.keepRunning")
    static let hostRow = SettingsRowID("background.host")
    static let checkRow = SettingsRowID("background.check")

    @Environment(DurableHost.self) private var host: DurableHost?
    @Environment(\.settingsPlainly) private var plainly
    @Environment(CommandRegistry.self) private var commands
    @AppStorage(HostSessions.defaultsKey) private var keepsRunning = HostSessions.defaultValue
    @State private var isCheckingMac = false

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Background",
                description: Text(
                    "Agents keep working when you quit Native or close its window, and pick up where they left off after a crash, an update or a restart of your Mac."
                ),
                plainly: .init(
                    title: "While You're Away",
                    description: "Agents keep working when you quit Native or step away from your Mac."))
            if let host, needsRelaunch(host) {
                relaunchNotice
            } else if let fallback = host?.placement.fallback {
                fallbackNotice(fallback)
            }
            SettingsRowGroup {
                SettingsRow(
                    id: Self.keepRunningRow,
                    "Keep agents running when Native quits", plainly: .keepRunning,
                    description: Text(
                        "Agents run in Native's background host, listed as Native under Login Items in System Settings. Turn this off to run them inside Native, so quitting stops them."
                    ),
                    detail: host?.placement.outlivesApp == true && keepsRunning ? Text(quitAndStopHint) : nil
                ) {
                    SettingsSwitch("Keep agents running when Native quits", isOn: $keepsRunning)
                }
                if let host {
                    hostRow(host)
                }
                if let client = host?.client, HostDoctorSheet.isAvailable {
                    checkRow(client)
                }
            }
        }
    }

    private var quitAndStopHint: String {
        let keys = commands.shortcut(for: .appQuitAndStopAgents).map { " (\($0.displayString))" } ?? ""
        return "To stop them when you quit, use Native ▸ Quit Native and Stop Agents\(keys)."
    }

    /// The setting differs from what this run does in a way the user would notice. Agents already
    /// stop with the app in a fallback, so turning the setting off there changes nothing yet.
    private func needsRelaunch(_ host: DurableHost) -> Bool {
        switch host.placement {
        case .inApp: keepsRunning
        case .background: !keepsRunning
        case .pending, .attached, .inAppFallback: false
        }
    }

    private var relaunchNotice: some View {
        NoticeBanner(
            tone: .info,
            systemImage: "arrow.clockwise",
            title: keepsRunning
                ? "Agents keep running after you quit from the next time Native opens"
                : "Agents stop when you quit Native from now on",
            detail: keepsRunning
                ? "Until then, agents run inside Native and stop when it quits."
                : "Quitting stops the background host and its agents. From the next time Native opens, agents run inside it."
        ) {
            #if os(macOS)
            Button("Relaunch Now") { AppRelaunch.relaunch() }
                .buttonStyle(.ds(.secondary))
            #endif
        }
    }

    @ViewBuilder
    private func fallbackNotice(_ fallback: HostFallback) -> some View {
        switch fallback {
        case .backgroundNotAllowed:
            NoticeBanner(
                tone: .info,
                systemImage: "moon.zzz",
                title: "Native isn't allowed to run in the background",
                detail:
                    "It's turned off under Allow in the Background in Login Items, so agents stop when Native quits. Turn Native on there, then relaunch Native."
            ) {
                #if os(macOS)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.ds(.secondary))
                #endif
            }
        case .registrationFailed(let reason), .didNotStart(let reason):
            ErrorState(
                "Native's background host didn't start",
                recovery: "Agents stop when Native quits this time. Native tries again the next time it opens.",
                details: reason)
        }
    }

    /// The host doctor (native/HostDoctor), for this Mac.
    private func checkRow(_ client: NativeHostClient) -> some View {
        SettingsRow(
            id: Self.checkRow, "Check this Mac",
            description: Text(
                "What agents need here, and whether this Mac logs in and stays awake on its own, as a Mac mini running agents should. Checking changes nothing."
            )
        ) {
            Button("Check This Mac…") { isCheckingMac = true }
                .buttonStyle(.settings)
        }
        .sheet(isPresented: $isCheckingMac) {
            HostDoctorSheet(hostName: "This Mac", client: client)
        }
    }

    private func hostRow(_ host: DurableHost) -> some View {
        SettingsRow(
            id: Self.hostRow, "Background host", plainly: .backgroundHelper,
            description: Text(hostDescription(host))
        ) {
            if host.isUnavailable {
                Button("Restart Host") { Task { await host.startHostAgain() } }
            } else {
                SettingsValue(hostValue(host))
            }
        }
    }

    private func hostDescription(_ host: DurableHost) -> String {
        switch host.placement {
        case .background:
            switch host.workingTasks {
            case 0: plainly ? "No agents running." : "Nothing is running right now."
            case 1: "1 task is working."
            default: "\(host.workingTasks) tasks are working."
            }
        case .attached: "Native started it for this session, so it stops when Native quits."
        case .inApp, .inAppFallback, .pending: "Agents run inside Native."
        }
    }

    private func hostValue(_ host: DurableHost) -> String {
        guard host.placement.usesHost else { return "Not running" }
        return switch host.connection {
        case .connected(let info): "Running since \(DSFormat.time(info.startedAt, now: .now))"
        case .reconnecting: "Reconnecting…"
        case .unreachable: "Not responding"
        case .incompatible(_, let peer): "Native \(peer.version)"
        case .connecting, nil: "Starting…"
        }
    }
}
