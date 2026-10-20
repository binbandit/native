#if NATIVE_HOSTSUI_WIP
import NativeHostProtocol
import SwiftUI

/// One device on Settings ▸ Hosts: its row (glyph, name, state, what it runs on), what's wrong
/// when something is and what to do about it, and its agents while it's online.
struct HostSettingsBlock: View {
    let host: HostDisplay
    let actions: Actions

    /// What the block's controls do; the page owns the sheets and confirmations they open.
    struct Actions {
        var rename: () -> Void
        var setLook: (HostLook) -> Void
        var remove: () -> Void
        var reconnect: () -> Void
        /// Sets the host's Keep Awake; returns why that failed, if it did.
        var setKeepAwake: (KeepAwakeMode) async -> String?
        /// Opens the check of the host's setup, while it can be checked.
        var check: (() -> Void)?
        var pairAgain: (() -> Void)?
        var openBackgroundSettings: () -> Void
        var signIn: (HostAgentDisplay, HostSignInMethod?) -> Void
        /// Returns why looking again failed, if it did.
        var checkAgain: (HostAgentDisplay) async -> String?
    }

    @State private var keepAwakeFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.lg) {
                SettingsIconTile {
                    HostGlyph(
                        look: host.look, size: SettingsMetrics.tileGlyph, weight: .thin,
                        isDimmed: !host.state.availability.isOnline)
                }
                row
            }
            Group {
                if let keepAwakeFailure {
                    ErrorState("Couldn't change Keep Awake on \(host.name)", suggestion: keepAwakeFailure)
                }
                notice
                if host.state == .online, !host.agents.isEmpty {
                    agents
                }
            }
            // Under the name, past the glyph's tile.
            .padding(.leading, SettingsMetrics.iconTile + DS.Space.lg)
        }
        .settingsRevealTarget(HostsSettingsPage.rowID(host.device))
    }

    private var row: some View {
        SettingsRow(
            title: Text(host.name),
            description: description.map { Text($0) },
            detail: host.isThisMac ? nil : Text(host.sessions.line)
        ) {
            Badge(host.state.title, tone: host.state.tone, style: .soft)
        } control: {
            menu
        }
    }

    /// The machine it is and what it runs, or what Native is doing while that isn't known.
    private var description: String? {
        let machine = host.machine.line(now: .now)
        let parts = [host.machineName, machine].compactMap(\.self)
        if !parts.isEmpty, case .online = host.state { return parts.joined(separator: " · ") }
        switch host.state {
        case .connecting: return "Native is connecting to \(host.name)."
        case .reconnecting(let reason): return "The connection dropped, and Native is reconnecting. \(reason)"
        default: return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    // MARK: - What's wrong

    @ViewBuilder private var notice: some View {
        switch host.state {
        case .online, .connecting, .reconnecting:
            EmptyView()
        case .offline(let reason, let lastConnected):
            NoticeBanner(
                tone: .warning, systemImage: "bolt.horizontal.circle", title: "\(host.name) isn't reachable",
                detail: "Its tasks keep running there while it's on. Native keeps trying to connect.",
                footnote: [reason, lastConnected.map(Self.lastConnected)].compactMap(\.self).joined(separator: " ")
            ) {
                Button("Try Now", action: actions.reconnect)
                    .buttonStyle(.ds(.secondary))
            }
        case .needsUpdate(let message):
            NoticeBanner(
                tone: .warning, systemImage: "arrow.down.circle", title: "\(host.name) runs another version of Native",
                detail: message,
                footnote: "Its tasks keep running. This Mac follows them again once both run the same version.")
        case .pairingEnded(let reason):
            NoticeBanner(
                tone: .danger, systemImage: "link", title: "\(host.name) ended the pairing", detail: reason,
                footnote: "Pair it again to run tasks there, or remove it from this list."
            ) {
                if let pairAgain = actions.pairAgain {
                    Button("Pair Again…", action: pairAgain)
                        .buttonStyle(.ds(.secondary))
                }
            }
        }
    }

    private func setKeepAwake(_ mode: KeepAwakeMode) {
        keepAwakeFailure = nil
        Task { keepAwakeFailure = await actions.setKeepAwake(mode) }
    }

    private static func title(of mode: KeepAwakeMode) -> String {
        switch mode {
        case .off, .unknown: "Off"
        case .whileAgentsWork: "While Agents Work"
        case .on: "On"
        }
    }

    private static func lastConnected(_ date: Date) -> String {
        let age = DSFormat.compactAge(date, now: .now)
        return age == "now" ? "Last connected just now." : "Last connected \(age) ago."
    }

    // MARK: - Agents

    private var agents: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(host.agents) { agent in
                HostAgentSettingsRow(
                    agent: agent, hostName: host.name, isThisMac: host.isThisMac,
                    signIn: { actions.signIn(agent, $0) }, checkAgain: { await actions.checkAgain(agent) })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agents on \(host.name)")
    }

    // MARK: - Actions

    private var menu: some View {
        Menu {
            if host.isThisMac {
                Button("Background Settings…", action: actions.openBackgroundSettings)
            } else {
                Button("Rename…", action: actions.rename)
            }
            if let check = actions.check {
                Button("Check \(host.name)…", action: check)
            }
            if let mode = host.keepAwakeMode {
                Picker(
                    "Keep Awake",
                    selection: Binding(get: { mode }, set: { newMode in setKeepAwake(newMode) })
                ) {
                    ForEach(KeepAwakeMode.choices) { choice in
                        Text(Self.title(of: choice)).tag(choice)
                    }
                }
            }
            Picker(
                "Symbol",
                selection: Binding(
                    get: { host.look.symbol }, set: { actions.setLook(HostLook(symbol: $0, tint: host.look.tint)) })
            ) {
                ForEach(HostSymbol.allCases) { symbol in
                    Label(symbol.title, systemImage: symbol.systemImage).tag(symbol)
                }
            }
            Picker(
                "Color",
                selection: Binding(
                    get: { host.look.tint }, set: { actions.setLook(HostLook(symbol: host.look.symbol, tint: $0)) })
            ) {
                ForEach(HostTint.allCases) { tint in
                    Text(tint.title).tag(tint)
                }
            }
            if !host.isThisMac {
                Divider()
                Button("Remove…", role: .destructive, action: actions.remove)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.ds(.ghost, size: .medium))
        .accessibilityLabel("Options for \(host.name)")
    }
}
#endif
