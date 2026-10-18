import AppKit
import SwiftUI
import Terminal

/// Settings › Terminal › Shell: the user's login shell by default, a shell from `/etc/shells`, or
/// any program they pick. New tabs use it; a Ghostty config's own `command` wins while it's in use.
struct TerminalShellRow: View {
    let store: TerminalStore

    /// The select's choices: a shell, or "Other…" to pick a program.
    private enum Choice: Hashable {
        case shell(TerminalShell)
        case other
    }

    var body: some View {
        SettingsRow(
            id: TerminalSettingsPage.shellRow,
            "Shell",
            description: Text("Runs as a login shell, so your profile loads. Applies to new tabs."),
            detail: note
        ) {
            SettingsSelect(
                label: "Shell", selection: selection, options: options, width: TerminalSettingsPage.fontSelectWidth)
        }
    }

    private var options: [SettingsSelect<Choice>.Option] {
        let login = TerminalLoginShell.current
        let listed = Self.registeredShells
        var shells: [SettingsSelect<Choice>.Option] = [
            .init(value: .shell(.login), title: "Login shell (\(URL(filePath: login).lastPathComponent))")
        ]
        shells += listed.map { .init(value: .shell(.path($0)), title: $0) }
        if case .path(let custom) = store.preferences.settings.shell, !listed.contains(custom) {
            shells.append(.init(value: .shell(.path(custom)), title: custom))
        }
        return shells + [.init(value: .other, title: "Other…")]
    }

    private var selection: Binding<Choice> {
        Binding(
            get: { .shell(store.preferences.settings.shell) },
            set: { choice in
                switch choice {
                case .shell(let shell): store.preferences.settings.shell = shell
                case .other: chooseProgram()
                }
            }
        )
    }

    /// Why the chosen shell won't run, or that the Ghostty config overrides it.
    private var note: Text? {
        let settings = store.preferences.settings
        let path = settings.shell.path(loginShell: TerminalLoginShell.current)
        if !TerminalLoginShell.isRunnable(path) {
            return Text("\(path) can't be run; terminals offer \(TerminalShell.fallback) instead.")
        }
        guard settings.usesGhosttyConfig, case .ghostty = store.configStatus,
            let command = GhosttyConfigFile.load(.current, home: .homeDirectory).lastValue("command"), !command.isEmpty
        else { return nil }
        return Text("Your Ghostty config's command runs instead: \(command)")
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.message = "Choose the shell new terminal tabs run."
        panel.prompt = "Use Shell"
        panel.directoryURL = URL(filePath: "/bin")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.preferences.settings.shell = .path(url.path(percentEncoded: false))
    }

    /// The shells registered on this Mac, from `/etc/shells`.
    private static var registeredShells: [String] {
        guard let text = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }
    }
}
