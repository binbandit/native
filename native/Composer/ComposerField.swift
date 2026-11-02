import ACP
import SwiftUI

#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif

/// The editor and control row share a field, but only the editor grows or scrolls.
struct ComposerField<Attachments: View>: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var openMenu: ComposerBottomRow.Menu?
    var editorFocus: FocusState<Bool>.Binding? = nil
    let state: ComposerRowState
    let actions: ComposerRowActions
    var placeholder = "What would you like to work on?"
    var files: [String] = []
    var commands: [ComposerSlashCommand] = []
    var isDropTargeted = false
    var onQuery: (String?) -> Void = { _ in }
    var onCommand: (ComposerSlashCommand) -> Void = { _ in }
    var onAttachments: ([DSTextInputAttachment]) -> Void = { _ in }
    var onEscape: () -> Bool = { false }
    var onEvent: (DSTextInputEvent, NSRange) -> Bool = { _, _ in false }
    @ViewBuilder var attachments: () -> Attachments

    @State private var document = TextInputDocument()
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var inputState: DSTextInputState?
    @State private var highlighted = 0
    @State private var dismissed = false

    private var completions: [ComposerFieldCompletion] {
        guard !dismissed, isFocused, let query = inputState?.query else { return [] }
        let display = document.displayText
        if let range = Range(selection, in: display), PromptCode.isInBlock(range.upperBound, in: display) { return [] }
        switch query.kind {
        case .file: return files.map { .file($0) }
        case .command:
            return (SlashCommandQuery(draft: "/" + query.text)?.matches(in: commands) ?? []).map { .command($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            attachments()
            editor
                .overlay(alignment: .topLeading) {
                    GeometryReader { geometry in
                        if !completions.isEmpty, let caret = inputState?.caret {
                            let width = min(DS.ComposerField.completionWidth, geometry.size.width)
                            ComposerFieldSuggestions(
                                items: completions, highlighted: $highlighted, choose: accept
                            )
                            .frame(width: width)
                            .padding(.bottom, DS.Space.xs)
                            .frame(height: 0, alignment: .bottom)
                            .offset(x: max(0, min(caret.minX, geometry.size.width - width)), y: max(0, caret.minY))
                        }
                    }
                }
                .padding(.horizontal, DS.Space.xs)
                .padding(.top, DS.Space.xs)
                .zIndex(1)
            ComposerBottomRow(state: state, actions: actions, openMenu: $openMenu)
        }
        .background(.dsSurface, in: .rect(cornerRadius: DS.ComposerField.radius))
        .overlay {
            RoundedRectangle(cornerRadius: DS.ComposerField.radius)
                .strokeBorder(isDropTargeted ? Color.dsAccent : .dsBorder, lineWidth: DS.ComposerRow.borderWidth)
                .allowsHitTesting(false)
        }
        .onAppear { synchronizeText() }
        .onChange(of: text) { synchronizeText() }
        .onChange(of: document) { _, value in
            if text != value.plainText { text = value.plainText }
        }
        .onChange(of: inputState?.query) { _, query in
            highlighted = 0
            dismissed = false
            onQuery(query?.kind == .file ? query?.text : nil)
        }
        .onChange(of: completions) { highlighted = min(highlighted, max(0, completions.count - 1)) }
    }

    @ViewBuilder
    private var editor: some View {
        let input = DSTextInput(
            document: $document, placeholder: placeholder, isFocused: $isFocused, selection: $selection,
            onSubmit: actions.send, onKey: handleKey, onEvent: handleEvent, onAttachments: onAttachments,
            onStateChange: { inputState = $0 })
        // SwiftUI clears an unregistered FocusState on draft updates. Only the editor owns it, not the row.
        if let editorFocus { input.focused(editorFocus) } else { input }
    }

    private func synchronizeText() {
        guard document.plainText != text else { return }
        document = TextInputDocument(text)
        selection = NSRange(location: document.displayText.utf16.count, length: 0)
    }

    private func handleKey(_ key: DSTextInputKey) -> Bool {
        if !completions.isEmpty {
            switch key {
            case .up: highlighted = max(0, highlighted - 1)
            case .down: highlighted = min(completions.count - 1, highlighted + 1)
            case .submit, .tab:
                if completions.indices.contains(highlighted) { accept(completions[highlighted]) }
            case .escape: dismissed = true
            }
            return true
        }
        if key == .escape { return onEscape() }
        return false
    }

    private func handleEvent(_ event: DSTextInputEvent) -> Bool {
        if event.modifiers.isEmpty, !completions.isEmpty { return false }
        let display = document.displayText
        if let range = Range(selection, in: display), PromptCode.isInBlock(range.upperBound, in: display) {
            let edit: PromptCode.Edit?
            switch event.key {
            case .return where event.modifiers.isEmpty:
                edit = PromptCode.newline(in: display, replacing: range)
            case .tab where event.modifiers.isEmpty:
                edit = PromptCode.indent(in: display, selection: range)
            case .tab where event.modifiers == .shift:
                edit = PromptCode.outdent(in: display, selection: range)
            default: edit = nil
            }
            if let edit {
                // Replace only the changed span so mentions elsewhere keep their atomic identity.
                let prefix = zip(display, edit.text).prefix(while: { $0 == $1 }).count
                let oldTail = display.dropFirst(prefix)
                let newTail = edit.text.dropFirst(prefix)
                let suffix = zip(oldTail.reversed(), newTail.reversed()).prefix(while: { $0 == $1 }).count
                let oldStart = display.index(display.startIndex, offsetBy: prefix)
                let oldEnd = display.index(display.endIndex, offsetBy: -suffix)
                let newStart = edit.text.index(edit.text.startIndex, offsetBy: prefix)
                let newEnd = edit.text.index(edit.text.endIndex, offsetBy: -suffix)
                if let updated = document.replacing(
                    NSRange(oldStart..<oldEnd, in: display), with: .init(String(edit.text[newStart..<newEnd])))
                {
                    document = updated
                    text = updated.plainText
                    selection = NSRange(edit.selection, in: edit.text)
                }
                return true
            }
        }
        return onEvent(event, selection)
    }

    private func accept(_ completion: ComposerFieldCompletion) {
        guard let query = inputState?.query else { return }
        guard let result = completion.inserting(in: document, query: query) else { return }
        document = result.document
        text = result.document.plainText
        selection = result.selection
        dismissed = !result.continues
        isFocused = true
        if case .command(let command) = completion { onCommand(command) }
    }
}
