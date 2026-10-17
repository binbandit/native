import ACP
import SwiftUI

/// The sidebar's footer, after the reference app's: a hairline, then the agents' health where the reference app
/// shows the plan badge, and Help and Settings at the trailing edge (the reference app's `px-4 py-3`, 20pt
/// between the icons).
struct SidebarFooter: View {
    var body: some View {
        HStack(spacing: DS.Space.lg) {
            AgentHealthBar()
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.xl + DS.Space.xs) {
                SidebarHelpMenu()
                SettingsButton()
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .overlay(alignment: .top) {
            SeparatorLine()
                .padding(.horizontal, DS.Space.lg)
        }
    }
}

/// Opens the Settings window (the reference app's gear, "Settings ⌘,").
private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            FooterGlyph(systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
    }
}

/// the reference app's "?" menu: keyboard shortcuts, the protocol's docs, and each agent's version and
/// restart, with the versions line at the bottom.
private struct SidebarHelpMenu: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingShortcuts = false

    var body: some View {
        Menu {
            Button("Keyboard Shortcuts", systemImage: "keyboard") {
                isShowingShortcuts = true
            }
            Link(destination: Self.protocolDocs) {
                Label("Agent Client Protocol Docs", systemImage: "book")
            }
            Divider()
            Section("Agents") {
                ForEach(model.agents, id: \.agent.id) { runtime in
                    Button("Restart \(runtime.agent.displayName)", systemImage: "arrow.clockwise") {
                        Task { await model.restart(runtime.agent.id) }
                    }
                    .disabled(runtime.status == .starting)
                }
            }
            Divider()
            Text(versions)
        } label: {
            FooterGlyph(systemImage: "questionmark.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Help")
        .accessibilityLabel("Help")
        .sheet(isPresented: $isShowingShortcuts) {
            KeyboardShortcutsView()
        }
    }

    private static let protocolDocs = URL(string: "https://agentclientprotocol.com") ?? URL(filePath: "/")

    /// "Native 1.0 · Claude Code 2.1.3 · Codex 0.40", as the reference app ends its help menu.
    private var versions: String {
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let agents = model.agents.map { runtime in
            [runtime.agent.displayName, runtime.info?.version ?? "…"].joined(separator: " ")
        }
        return (["Native \(app ?? "…")"] + agents).joined(separator: " · ")
    }
}

/// A footer icon: the reference app's 16pt muted glyphs that brighten on hover, with no fill.
private struct FooterGlyph: View {
    let systemImage: String

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.dsCallout)
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
            .contentShape(.rect)
            .trackHover($isHovered)
    }
}
