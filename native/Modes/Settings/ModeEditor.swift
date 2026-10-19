import Modes
import SwiftUI

/// Adds or edits one of the user's own modes, as a sheet: its name, symbol and one-line
/// description, the instructions the agent gets, and the settings it applies. ⌘Return saves,
/// Escape cancels.
struct ModeEditor: View {
    /// What the sheet edits.
    enum Subject: Identifiable {
        case new
        /// A new mode starting as a copy of another (Native's own, or a project's).
        case copy(Mode)
        case existing(Mode)

        var id: String {
            switch self {
            case .new: "new"
            case .copy(let mode): "copy-\(mode.id.rawValue)"
            case .existing(let mode): mode.id.rawValue
            }
        }
    }

    let subject: Subject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var draft: Mode
    private let library = ModeLibrary.shared

    /// Symbols to pick from, for the kinds of work a mode is for.
    private static let symbols = [
        "wand.and.stars", "hammer", "ladybug", "text.magnifyingglass", "questionmark.bubble", "list.bullet.clipboard",
        "lock.shield", "checkmark.seal", "doc.text", "paintbrush", "gauge.with.dots.needle.67percent", "testtube.2",
        "arrow.triangle.branch", "scissors", "book", "graduationcap", "bolt", "hare", "tortoise", "sparkles",
    ]

    init(subject: Subject) {
        self.subject = subject
        let library = ModeLibrary.shared
        switch subject {
        case .new:
            _draft = State(
                initialValue: Mode(
                    id: .custom(UUID().uuidString), name: "", symbol: ModeFile.defaultSymbol, summary: "",
                    instructions: "", source: .custom))
        case .copy(let mode):
            var copy = mode
            copy.id = .custom(UUID().uuidString)
            copy.name = library.freeName(for: mode.name)
            copy.source = .custom
            _draft = State(initialValue: copy)
        case .existing(let mode):
            _draft = State(initialValue: mode)
        }
    }

    private var isNew: Bool {
        if case .existing = subject { false } else { true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    "The agent gets the instructions with your next message after you pick the mode, and the settings apply as you pick it."
                )
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: DS.Space.lg) {
                field("Name") {
                    TextField("Write Docs", text: $draft.name)
                        .settingsField()
                }
                field("Description") {
                    TextField("What it's for, in a line", text: $draft.summary)
                        .settingsField()
                }
            }
            field("Symbol") {
                FlowLayout(spacing: DS.Space.xs) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        IconButton(symbol, systemImage: symbol, size: .medium, isActive: draft.symbol == symbol) {
                            draft.symbol = symbol
                        }
                        .accessibilityAddTraits(draft.symbol == symbol ? .isSelected : [])
                    }
                }
            }
            field("Instructions") {
                TextField(
                    "What the agent should do in this mode, step by step, in Markdown", text: $draft.instructions,
                    axis: .vertical
                )
                .lineLimit(6...14)
                .padding(.vertical, DS.Space.sm)
                .settingsField()
            }
            HStack(alignment: .top, spacing: DS.Space.lg) {
                field("Autonomy") {
                    SettingsSelect(
                        label: "Autonomy", selection: $draft.settings.autonomy,
                        options: [.init(value: nil, title: "Keep the task's level")]
                            + ModeAutonomy.allCases.map { .init(value: $0, title: $0.title) },
                        width: ModeMetrics.editorWidth / 2 - DS.Space.lg)
                }
                field("Model") {
                    TextField("Keep the task's model", text: optional(\.model))
                        .settingsField()
                }
            }
            HStack(spacing: DS.Space.md) {
                SettingsSwitch("Use Plan Mode", isOn: $draft.settings.usesPlanMode)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Use the agent's plan mode")
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Text("It plans and changes nothing until you approve. An agent without one is kept read-only.")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            HStack(spacing: DS.Space.md) {
                if let problem {
                    Text(problem)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.ds(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Mode" : "Save") { save() }
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(problem != nil)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: ModeMetrics.editorWidth)
    }

    private var title: String {
        switch subject {
        case .new: "New Mode"
        case .copy(let mode): "New Mode from \(mode.name)"
        case .existing(let mode): "Edit \u{201C}\(mode.name)\u{201D}"
        }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An optional setting as text, where empty means unset.
    private func optional(_ keyPath: WritableKeyPath<ModeSettings, String?>) -> Binding<String> {
        Binding(
            get: { draft.settings[keyPath: keyPath] ?? "" },
            set: { draft.settings[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    /// Why it can't be saved yet, in a few words; nil when it can.
    private var problem: String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give it a name." }
        let others = (Mode.builtIn + library.custom).filter { $0.id != draft.id }
        if others.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            return "Another mode is called \(name)."
        }
        if draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Write what the agent should do."
        }
        return nil
    }

    private func save() {
        guard problem == nil else { return }
        var mode = draft
        mode.name = mode.name.trimmingCharacters(in: .whitespacesAndNewlines)
        mode.instructions = mode.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        mode.summary = mode.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode.summary.isEmpty {
            mode.summary = String(mode.instructions.prefix { !$0.isNewline }.prefix(90))
        }
        mode.settings.model = mode.settings.model?.trimmingCharacters(in: .whitespaces)
        if isNew {
            library.add(mode, undoManager: undoManager)
        } else {
            library.update(mode, undoManager: undoManager)
        }
        dismiss()
    }
}
