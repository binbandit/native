import NativeCommands
import SwiftUI

extension View {
    /// Puts the command palette over this window's content while it's open (⌘K).
    func commandPalette(_ palette: CommandPalette) -> some View {
        overlay {
            if palette.isPresented {
                CommandPaletteView(palette: palette)
                    .transition(.opacity.animation(.dsPopover))
            }
        }
        .onAppear { palette.windowAppeared() }
        .onDisappear { palette.windowDisappeared() }
    }
}

/// The command palette: a search field over grouped results, each row with its
/// shortcut, floating near the top of the window. ↑ and ↓ move, Return runs, Escape or a click
/// outside closes it. Rows are touch-sized on iPad.
struct CommandPaletteView: View {
    let palette: CommandPalette

    @State private var query = ""
    @State private var selection: CommandPaletteItem.ID?
    @FocusState private var isSearchFocused: Bool

    private static let width: CGFloat = 600
    private static let topInset: CGFloat = 72
    private static let listMaxHeight: CGFloat = 400
    private static let fieldHeight: CGFloat = 44

    var body: some View {
        let results = CommandPaletteResults(
            items: palette.items(for: query), query: query, recents: palette.recents)
        ZStack(alignment: .top) {
            // Clicking or tapping outside closes it, as a popover does.
            Color.clear
                .contentShape(.rect)
                .onTapGesture { palette.dismiss() }
                .accessibilityHidden(true)
            panel(results)
                .frame(maxWidth: Self.width)
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, Self.topInset)
        }
        .onAppear { isSearchFocused = true }
    }

    private func panel(_ results: CommandPaletteResults) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        return VStack(spacing: 0) {
            searchField(results)
            SeparatorLine()
            CommandPaletteList(
                results: results, query: query, selection: $selection, maxHeight: Self.listMaxHeight,
                onRun: run)
            SeparatorLine()
            CommandPaletteFooter()
        }
        .dsOverlayBackground(in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .dsShadow(.modal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Palette")
        .accessibilityAddTraits(.isModal)
    }

    private func searchField(_ results: CommandPaletteResults) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "magnifyingglass")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityHidden(true)
            TextField(
                "Search commands, tasks and settings", text: $query,
                prompt: Text("Type a command or search…").foregroundStyle(.dsTextTertiary)
            )
            .textFieldStyle(.plain)
            .font(.dsCallout)
            .foregroundStyle(.dsTextPrimary)
            .focused($isSearchFocused)
            .onKeyPress(.downArrow) { move(by: 1, in: results) }
            .onKeyPress(.upArrow) { move(by: -1, in: results) }
            // Emacs-style ⌃N and ⌃P, as macOS text fields and most palettes take them.
            .onKeyPress(keys: ["n", "p"]) { press in
                guard press.modifiers == .control else { return .ignored }
                return move(by: press.key == "n" ? 1 : -1, in: results)
            }
            .onKeyPress(.return) {
                if let row = selectedRow(in: results) {
                    run(row.item)
                }
                return .handled
            }
            .onKeyPress(.escape) {
                palette.dismiss()
                return .handled
            }
            .onChange(of: query) { selection = nil }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: Self.fieldHeight)
    }

    /// The highlighted row: the one the user moved to, or the first.
    private func selectedRow(in results: CommandPaletteResults) -> CommandPaletteResults.Row? {
        results.rows.first { $0.id == selection } ?? results.rows.first
    }

    private func move(by step: Int, in results: CommandPaletteResults) -> KeyPress.Result {
        guard !results.rows.isEmpty else { return .handled }
        let current = selectedRow(in: results).flatMap { row in results.rows.firstIndex { $0.id == row.id } } ?? 0
        let next = (current + step + results.rows.count) % results.rows.count
        selection = results.rows[next].id
        return .handled
    }

    private func run(_ item: CommandPaletteItem) {
        palette.run(item)
    }
}

/// The key hints along the bottom.
private struct CommandPaletteFooter: View {
    var body: some View {
        HStack(spacing: DS.Space.xl) {
            hint("↑↓", "Navigate")
            hint("↩", "Run")
            hint("esc", "Close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlMD)
        .accessibilityHidden(true)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Kbd(keys)
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }
}
