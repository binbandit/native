import NativeCommands
import SwiftUI
import UniformTypeIdentifiers

extension SettingsPane.ID {
    static let keyboardShortcuts = Self("keyboard-shortcuts")
}

extension SettingsPane {
    static let keyboardShortcuts = SettingsPane(
        id: .keyboardShortcuts,
        title: "Keyboard shortcuts",
        systemImage: "keyboard",
        group: .personal,
        order: 20,
        keywords: ["keys", "hotkeys", "remap", "bindings"],
        searchEntries: {
            let registry = CommandRegistry.shared
            let commands = registry.commands.map { command in
                SettingsSearchEntry(
                    id: ShortcutSettingsRow.rowID(command.id), title: command.title,
                    description: registry.shortcut(for: command.id)?.displayString ?? "",
                    keywords: command.keywords + (registry.shortcut(for: command.id)?.searchTerms ?? []))
            }
            let fixed = ShortcutReference.groups(followUp: .defaultValue).flatMap(\.shortcuts).map { shortcut in
                SettingsSearchEntry(
                    id: ShortcutReference.rowID(shortcut), title: shortcut.title, description: shortcut.note ?? "",
                    keywords: shortcut.keywords)
            }
            return commands + fixed
        },
        content: { KeyboardShortcutsSettingsPage() }
    )
}

/// Conductor's Keyboard shortcuts page, editable: every command by category, each shortcut a pill
/// that records a new one, with search by name or by keys, reset, and import and export. Below
/// them, the keys views answer themselves, which can't be changed.
struct KeyboardShortcutsSettingsPage: View {
    @Environment(CommandRegistry.self) private var registry

    var body: some View {
        KeyboardShortcutsEditor(registry: registry)
    }
}

private struct KeyboardShortcutsEditor: View {
    let registry: CommandRegistry
    @State private var editor: ShortcutEditor
    @State private var query = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isConfirmingReset = false
    @State private var exported: ShortcutsDocument?
    @State private var notice: ShortcutsNotice?
    @AppStorage(FollowUpBehavior.storageKey) private var followUp = FollowUpBehavior.defaultValue

    init(registry: CommandRegistry) {
        self.registry = registry
        _editor = State(initialValue: ShortcutEditor(registry: registry))
    }

    var body: some View {
        let filter = ShortcutFilter(query)
        let categories = CommandCategory.allCases.compactMap { category -> CategoryCommands? in
            let commands = registry.commands.filter { $0.category == category && filter.matches($0, in: registry) }
            return commands.isEmpty ? nil : CategoryCommands(category: category, commands: commands)
        }
        let fixed = ShortcutReference.groups(followUp: followUp).compactMap { group -> ShortcutReference.Group? in
            let shortcuts = group.shortcuts.filter(filter.matches)
            return shortcuts.isEmpty
                ? nil : ShortcutReference.Group(title: group.title, note: group.note, shortcuts: shortcuts)
        }
        SettingsPage {
            SettingsHeader(
                title: "Keyboard shortcuts",
                description: Text(
                    "Click a shortcut to record a new one; right-click for more. Tab, the arrow keys, Space and Escape work as they do everywhere on macOS."
                )
            ) {
                actions
            }
            if registry.isLocked {
                NoticeBanner(
                    tone: .info, systemImage: "lock", title: PolicyCenter.managedExplanation,
                    detail: "Your organization sets these shortcuts, so they can't be changed here.")
            }
            if let notice {
                NoticeBanner(
                    tone: notice.severity == .danger ? .danger : notice.severity == .warning ? .warning : .success,
                    title: notice.title, detail: notice.detail
                ) {
                    Button("Dismiss", systemImage: "xmark") { self.notice = nil }
                        .buttonStyle(.ds(.ghost, iconOnly: true))
                }
            }
            ShortcutSearchField(query: $query)
            VStack(alignment: .leading, spacing: DS.Space.xxxl) {
                ForEach(categories) { group in
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SettingsSubheading(group.category.title)
                        ShortcutOutline {
                            ForEach(group.commands) { ShortcutSettingsRow(command: $0, editor: editor) }
                        }
                    }
                }
                if !fixed.isEmpty {
                    SettingsSubheading("Keys inside views", note: "These work where you are and can't be changed.")
                        .padding(.bottom, -DS.Space.xl)
                }
                ForEach(fixed) { group in
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SettingsSubheading(group.title, note: group.note)
                        ShortcutOutline {
                            ForEach(group.shortcuts) { ShortcutReferenceRow(shortcut: $0) }
                        }
                    }
                }
                if categories.isEmpty, fixed.isEmpty {
                    Text("No shortcuts match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}")
                        .settingsText(.body)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
        }
        .onDisappear { editor.stopRecording() }
        .fileExporter(
            isPresented: $isExporting, document: exported, contentType: .json, defaultFilename: "Native Shortcuts"
        ) { result in
            if case .failure(let error) = result {
                notice = ShortcutsNotice(
                    severity: .danger, title: "Couldn't export shortcuts", detail: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importShortcuts(from: result)
        }
        .confirmationDialog("Reset every shortcut to Native's default?", isPresented: $isConfirmingReset) {
            Button("Reset All", role: .destructive) {
                editor.stopRecording()
                registry.resetAll()
                notice = ShortcutsNotice(severity: .success, title: "Every shortcut is back to its default")
            }
        } message: {
            Text("Export them first to keep your changes.")
        }
    }

    private var actions: some View {
        Menu {
            Button("Import…", systemImage: "square.and.arrow.down") { isImporting = true }
                .disabled(registry.isLocked)
            Button("Export…", systemImage: "square.and.arrow.up") { export() }
                .disabled(registry.userBindings.overrides.isEmpty)
            Divider()
            Button("Reset All…", systemImage: "arrow.uturn.backward", role: .destructive) { isConfirmingReset = true }
                .disabled(registry.isLocked || registry.userBindings.overrides.isEmpty)
        } label: {
            Label("Shortcut Actions", systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.ds(.secondary, size: .medium, iconOnly: true))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Import, export or reset shortcuts")
    }

    private func export() {
        do {
            exported = ShortcutsDocument(data: try registry.exportedFile())
            isExporting = true
        } catch {
            notice = ShortcutsNotice(
                severity: .danger, title: "Couldn't export shortcuts", detail: error.localizedDescription)
        }
    }

    private func importShortcuts(from result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let report = try registry.importFile(try Data(contentsOf: url))
            editor.stopRecording()
            notice = ShortcutsNotice(report: report, registry: registry)
        } catch let error as ShortcutFileError {
            notice = ShortcutsNotice(
                severity: .danger, title: "Couldn't import shortcuts",
                detail: error == .newerVersion
                    ? "The file is from a newer version of Native. Update Native, then import it again."
                    : "The file isn't a shortcuts file Native exported.")
        } catch {
            notice = ShortcutsNotice(
                severity: .danger, title: "Couldn't import shortcuts", detail: error.localizedDescription)
        }
    }
}

/// One category's commands, in registration order.
private struct CategoryCommands: Identifiable {
    let category: CommandCategory
    let commands: [NativeCommand]

    var id: CommandCategory { category }
}

/// Conductor `divide-y rounded-lg border`.
private struct ShortcutOutline<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        Group(subviews: content) { rows in
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SeparatorLine()
                    }
                    row
                }
            }
        }
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
    }
}

/// A key a view answers itself: read-only.
private struct ShortcutReferenceRow: View {
    let shortcut: ShortcutReference.Shortcut

    var body: some View {
        HStack(spacing: DS.Space.xxl) {
            VStack(alignment: .leading, spacing: 0) {
                Text(shortcut.title)
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let note = shortcut.note {
                    Text(note)
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.xs) {
                ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { index, keys in
                    if index > 0, let joiner = shortcut.joiner {
                        Text(joiner)
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                    }
                    SettingsKeycap(keys: keys)
                }
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .accessibilityElement(children: .combine)
        .settingsRevealTarget(ShortcutReference.rowID(shortcut))
    }
}

/// What the page tells the user after an import, an export or a reset.
private struct ShortcutsNotice {
    enum Severity {
        case success, warning, danger
    }

    var severity: Severity
    var title: String
    var detail: String?

    init(severity: Severity, title: String, detail: String? = nil) {
        self.severity = severity
        self.title = title
        self.detail = detail
    }

    @MainActor
    init(report: ShortcutBindings.Import, registry: CommandRegistry) {
        let count = report.applied.count
        severity = report.skipped.isEmpty ? .success : .warning
        title = "Imported \(count) \(count == 1 ? "shortcut" : "shortcuts")"
        guard !report.skipped.isEmpty else { return }
        func name(_ id: NativeCommand.ID) -> String { registry.command(id)?.title ?? id.rawValue }
        detail = report.skipped.map { skipped in
            switch skipped.reason {
            case .unknownCommand: "Skipped \(skipped.command): no such command in this version."
            case .unreadable(let text): "Skipped \(name(skipped.command)): \u{201C}\(text)\u{201D} isn't a shortcut."
            case .rejected(let shortcut, _):
                "Skipped \(name(skipped.command)): \(registry.rejection(for: shortcut) ?? shortcut.displayString)"
            case .conflict(let shortcut, let other):
                "Skipped \(name(skipped.command)): \(shortcut.displayString) is already \(name(other))."
            }
        }.joined(separator: "\n")
    }
}

/// The exported file, for `fileExporter`.
private struct ShortcutsDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
