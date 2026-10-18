import NativeCommands
import SwiftUI

/// What the Keyboard Shortcuts search keeps: commands whose name, keywords or keys contain every
/// word typed, or, when what's typed is a shortcut ("⌘K", "cmd shift a"), the commands bound to it.
struct ShortcutFilter {
    private let terms: [String]
    private let shortcut: KeyShortcut?

    init(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        terms = trimmed.lowercased().split(separator: " ").map(String.init)
        let candidates = [KeyShortcut(trimmed), KeyShortcut(trimmed.split(separator: " ").joined(separator: "+"))]
        // A bare key ("a") is a word to search for, not a shortcut.
        shortcut = candidates.lazy.compactMap { $0 }.first { !$0.modifiers.isEmpty }
    }

    func matches(_ command: NativeCommand, in registry: CommandRegistry) -> Bool {
        let bound = registry.shortcut(for: command.id)
        if let shortcut {
            return bound == shortcut
        }
        return matches(
            [command.title, command.id.rawValue, command.category.title] + command.keywords
                + (bound?.searchTerms ?? []))
    }

    func matches(_ reference: ShortcutReference.Shortcut) -> Bool {
        if let shortcut {
            return reference.keys.compactMap(KeyShortcut.init).contains(shortcut)
        }
        return matches([reference.title, reference.note ?? ""] + reference.keywords)
    }

    private func matches(_ fields: [String]) -> Bool {
        let text = fields.joined(separator: " ").lowercased()
        return terms.allSatisfy(text.contains)
    }
}

/// The page's search: by name, or by keys, typed ("cmd k") or pressed after clicking the
/// keyboard button, which fills in the shortcut pressed.
struct ShortcutSearchField: View {
    @Binding var query: String
    @State private var isRecording = false
    @State private var recorder = PlatformKeyRecorder()

    var body: some View {
        // The field brings the magnifier, the clear button, Escape to clear and the accent ring,
        // which stays on while recording.
        SearchField(
            "Search shortcuts", text: $query,
            prompt: Text(isRecording ? "Press the keys to find" : "Search by name or keys")
                .foregroundStyle(isRecording ? .dsAccentText : .dsTextTertiary),
            font: SettingsTextStyle.body.font, isHighlighted: isRecording
        ) {
            if PlatformKeyRecorder.capturesBeforeMenus {
                Button(isRecording ? "Stop Recording Keys" : "Search by Pressing Keys", systemImage: "keyboard") {
                    isRecording ? stopRecording() : startRecording()
                }
                .buttonStyle(.ds(.ghost, iconOnly: true))
                .foregroundStyle(isRecording ? .dsAccentText : .dsTextSecondary)
                .help("Press a shortcut to find what it does")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        recorder.start { _ in
        } onKey: { shortcut in
            stopRecording()
            if let shortcut, shortcut.key != .escape || !shortcut.modifiers.isEmpty {
                query = shortcut.displayString
            }
        }
    }

    private func stopRecording() {
        recorder.stop()
        isRecording = false
    }
}
