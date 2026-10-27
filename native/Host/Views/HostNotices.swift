import ACP
import NativeHostClient
import SwiftUI

#if os(macOS)
import ServiceManagement
#endif

/// Durable sessions' notices, above whatever the detail column shows: the host runs another version
/// than the app, the host is out of reach, host sessions still have Native's MCP server's old
/// address, why agents stop with the app this time (said once), and what agents did while Native
/// was closed. Nothing blocks the window; each says what Native is doing about it and offers the one
/// action that helps.
struct HostNotices: View {
    let host: DurableHost
    var updates: UpdateController?

    @Environment(AppModel.self) private var model

    var body: some View {
        if hasNotices {
            VStack(spacing: DS.Space.sm) {
                if host.versionStatus != .matched {
                    HostVersionNotice(
                        status: host.versionStatus,
                        appVersion: host.appVersionLabel,
                        onRestartHost: requestRestart,
                        onCheckForUpdates: { updates?.checkForUpdates() }
                    )
                }
                if host.isUnavailable {
                    unavailable
                }
                if let orchestration, orchestration.move != nil {
                    OrchestrationServerNotice(status: orchestration, onRestartHost: requestRestart)
                }
                if let fallback = host.fallbackNotice {
                    HostFallbackNotice(fallback: fallback, isAttached: host.placement.usesHost) {
                        host.dismissFallbackNotice()
                    }
                }
                if let away = host.away {
                    HostAwayCard(summary: away, title: title, open: open, onDismiss: host.dismissAway)
                }
                ForEach(awayHosts) { remote in
                    if let away = remote.away {
                        HostAwayCard(
                            summary: away, hostName: remote.name, title: title, open: { open($0, on: remote) },
                            onDismiss: remote.dismissAway)
                    }
                }
            }
            .padding(DS.Space.md)
            .animation(.dsStandard, value: host.away?.items.count)
        }
    }

    /// Restarts the host now, after asking when that would interrupt tasks.
    private func requestRestart() {
        host.requestHostRestart()
    }

    private var hasNotices: Bool {
        host.versionStatus != .matched || host.isUnavailable || orchestration?.move != nil
            || host.fallbackNotice != nil || host.away != nil || !awayHosts.isEmpty
    }

    /// Paired hosts with news from while this Mac was away from them.
    private var awayHosts: [RemoteHost] {
        model.hosts.all.filter { $0.away != nil }
    }

    /// Native's MCP server, which says when it had to move and host sessions still have its old address.
    private var orchestration: OrchestrationServerStatus? {
        OrchestrationServerNotice.status(in: model)
    }

    private var unavailable: some View {
        NoticeBanner(
            tone: .warning,
            systemImage: "bolt.horizontal.circle",
            title: "Native's background host isn't responding",
            detail:
                "Your tasks keep their place, and messages you send wait until it's back. Native keeps trying.",
            footnote: reason
        ) {
            Button("Restart Host") { Task { await host.startHostAgain() } }
                .buttonStyle(.ds(.secondary))
        }
    }

    private var reason: String? {
        if case .unreachable(let reason) = host.connection { reason } else { nil }
    }

    // MARK: - Tasks

    private func key(for item: AwaySummary.Item) -> SessionKey? {
        guard let agent = item.agentID, let session = item.agentSessionID else { return nil }
        return SessionKey(agent: AgentDefinition.ID(rawValue: agent), id: session)
    }

    /// The title the sidebar shows, which can differ from the host's (a rename, a generated title).
    private func title(_ item: AwaySummary.Item) -> String? {
        guard let key = key(for: item) else { return nil }
        return model.sessionList.first { $0.id == key }.map(model.title(for:))
    }

    /// Opens a task on a paired host, while the sidebar lists it.
    private func open(_ item: AwaySummary.Item, on remote: RemoteHost) -> (() -> Void)? {
        guard let key = key(for: item), model.sessionList.contains(where: { $0.id == key }) else { return nil }
        return {
            model.selection = key
            remote.removeAwayItem(item.id)
        }
    }

    private func open(_ item: AwaySummary.Item) -> (() -> Void)? {
        guard let key = key(for: item), model.catalog.contains(key) else { return nil }
        return {
            model.selection = key
            host.removeAwayItem(item.id)
        }
    }
}

/// Why agents stop when Native quits this time, though the user keeps them running: said once per
/// kind of reason, with the fix when there's one.
private struct HostFallbackNotice: View {
    let fallback: HostFallback
    /// A host Native started itself runs the agents, rather than the app.
    let isAttached: Bool
    let onDismiss: () -> Void

    var body: some View {
        NoticeBanner(
            tone: fallback == .backgroundNotAllowed ? .info : .warning,
            systemImage: "moon.zzz",
            title: "Agents stop when you quit Native",
            detail: detail,
            footnote: fallback.reason
        ) {
            #if os(macOS)
            if fallback == .backgroundNotAllowed {
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.ds(.secondary))
            }
            #endif
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .buttonStyle(.ds(.ghost, iconOnly: true))
                .help("Dismiss")
        }
    }

    private var detail: String {
        switch fallback {
        case .backgroundNotAllowed:
            "Native is turned off under Allow in the Background in Login Items, so it runs agents only while it's open. Turn it on there to keep them working after you quit."
        case .registrationFailed, .didNotStart:
            isAttached
                ? "Native's background host couldn't start, so Native runs agents only while it's open. It tries again the next time Native opens."
                : "Native's background host didn't start, so agents run inside Native, as before, and stop when it quits. It tries again the next time Native opens."
        }
    }
}
