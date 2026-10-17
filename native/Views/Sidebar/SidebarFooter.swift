import ACP
import SwiftUI

/// The sidebar's footer, after the reference app's: a hairline, then Help and Settings at the trailing edge
/// (the reference app's `px-4 py-3`, 20pt between the icons). Agents' health lives on Home, in Settings ▸
/// Agents and in the Help menu, not here.
struct SidebarFooter: View {
    var body: some View {
        HStack(spacing: DS.Space.xl + DS.Space.xs) {
            Spacer(minLength: 0)
            SidebarHelpMenu()
            SettingsButton()
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .overlay(alignment: .top) {
            SeparatorLine()
                .padding(.horizontal, DS.Space.lg)
        }
    }
}

/// Opens the Settings window (the reference app's gear, "Settings ⌘,"). iPadOS has no Settings scene; the
/// app presents settings there itself, so the gear isn't shown.
private struct SettingsButton: View {
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        Button {
            settings.open()
        } label: {
            FooterGlyph(systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
    }
}

/// the reference app's "?" menu: keyboard shortcuts, the protocol's docs, signing in to and restarting each
/// agent, with the versions line at the bottom.
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
                    // Signing in was the footer's job; it lives here now, next to Restart.
                    if runtime.isReady, runtime.needsSignIn, !runtime.authMethods.isEmpty {
                        Menu("Sign In to \(runtime.agent.displayName)") {
                            ForEach(runtime.authMethods, id: \.id) { method in
                                Button(method.name) {
                                    Task { await model.signIn(to: runtime.agent.id, with: method) }
                                }
                                .disabled(runtime.isSigningIn)
                            }
                        }
                    }
                    Button(
                        runtime.status.canRetry
                            ? "Retry \(runtime.agent.displayName)" : "Restart \(runtime.agent.displayName)",
                        systemImage: "arrow.clockwise"
                    ) {
                        Task { await model.restart(runtime.agent.id) }
                    }
                    .disabled(runtime.status == .starting)
                    .help(runtime.status.guidance ?? runtime.status.label)
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
            .dsHitTarget(DS.Size.rowLeading)
            .trackHover($isHovered)
    }
}
