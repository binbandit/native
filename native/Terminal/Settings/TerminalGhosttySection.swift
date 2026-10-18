import SwiftUI
import Terminal

/// Settings › Terminal's Ghostty rows: use the user's Ghostty config live, or import it once into
/// Native's settings. Both only read the user's files.
struct TerminalGhosttySection: View {
    let store: TerminalStore

    /// The import being previewed.
    @State private var pendingImport: PendingImport?

    private struct PendingImport: Identifiable {
        let id = UUID()
        let value: TerminalImport
    }

    var body: some View {
        @Bindable var preferences = store.preferences
        let usesGhostty = preferences.settings.usesGhosttyConfig
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRowGroup {
                SettingsRow(
                    id: TerminalSettingsPage.ghosttyRow,
                    "Use my Ghostty settings",
                    description: Text(
                        "Terminals load your Ghostty config: its theme, fonts, cursor, padding and key bindings. "
                            + "It replaces Native's terminal settings and code theme, and Native never changes it."),
                    detail: detail
                ) {
                    SettingsSwitch("Use my Ghostty settings", isOn: $preferences.settings.usesGhosttyConfig)
                }
                SettingsRow(
                    id: TerminalSettingsPage.importRow,
                    "Import from Ghostty",
                    description: Text(
                        "Copy your Ghostty font, colors, cursor and scrollback into Native's settings once, "
                            + "without a live link. You'll see what changes first.")
                ) {
                    Button("Import…") { pendingImport = PendingImport(value: store.readGhosttyImport()) }
                        .disabled(usesGhostty)
                }
            }
            if usesGhostty {
                status
            } else if store.settingsBeforeImport != nil {
                NoticeBanner(
                    tone: .success, title: "Imported from Ghostty",
                    detail: "Native's terminal settings now match your Ghostty config."
                ) {
                    Button("Undo") { store.undoImport() }
                        .buttonStyle(.ds(.secondary))
                }
            }
        }
        .sheet(item: $pendingImport) { pending in
            TerminalImportSheet(
                ghosttyImport: pending.value,
                current: preferences.settings,
                apply: {
                    store.applyImport(pending.value)
                    pendingImport = nil
                },
                cancel: { pendingImport = nil }
            )
        }
    }

    /// Which files are in use, under the switch.
    private var detail: Text? {
        guard store.preferences.settings.usesGhosttyConfig, case .ghostty(let files) = store.configStatus,
            let first = files.first
        else { return nil }
        let more = files.count > 1 ? " and \(files.count - 1) more" : ""
        return Text("Reading \(first.abbreviatedPath)\(more). Saved changes apply right away.")
    }

    @ViewBuilder private var status: some View {
        switch store.configStatus {
        case .ghosttyNotFound(let searched):
            NoticeBanner(
                tone: .info, title: "No Ghostty config found",
                detail:
                    "Native looks in \(searched.map { $0.deletingLastPathComponent() }.uniqued.map(\.abbreviatedPath).joined(separator: " and ")). "
                    + "Its own settings apply until you create one there; you don't need Ghostty installed.",
                footnote: themesNote
            ) {
                Button("Check Again") { store.reloadGhosttyConfig() }
                    .buttonStyle(.ds(.secondary))
            }
        case .ghosttyInvalid(_, let diagnostics):
            ErrorState(
                diagnostics.count == 1
                    ? "Your Ghostty config has a problem" : "Your Ghostty config has \(diagnostics.count) problems",
                recovery: "Native is using its own terminal settings until it's fixed.",
                suggestion: [diagnostics.first, themesNote].compactMap(\.self).joined(separator: " "),
                details: diagnostics.joined(separator: "\n"),
                primary: .init("Reload") { store.reloadGhosttyConfig() }
            )
        case .ghostty:
            if let themesNote {
                NoticeBanner(tone: .info, title: "Ghostty isn't installed", detail: themesNote) {
                    Button("Reload") { store.reloadGhosttyConfig() }
                        .buttonStyle(.ds(.secondary))
                }
            }
        case .ghosttyPending:
            if store.availability != .available {
                NoticeBanner(
                    tone: .info, title: "Terminal isn't available in this build",
                    detail: "Your Ghostty settings apply once Native is built with libghostty."
                ) { EmptyView() }
            }
        case .native:
            EmptyView()
        }
    }

    /// Theme names resolve in Ghostty.app's themes and the user's own; without the app, only theirs.
    private var themesNote: String? {
        guard GhosttyConfigLocations.ghosttyThemes == nil else { return nil }
        let themes = GhosttyConfigLocations.current.userThemes.abbreviatedPath
        return "Ghostty isn't installed, so theme names are found only in \(themes)."
    }
}

extension Sequence where Element: Hashable {
    /// The elements in order, without repeats.
    fileprivate var uniqued: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
