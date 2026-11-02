import SwiftUI
import TextInput
@testable import Native
import SwiftUI

#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif

/// The editor and control row share a field, but only the editor grows or scrolls.
struct ComposerFieldBaseline<Attachments: View>: View {
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
    @ViewBuilder var attachments: () -> Attachments

    @State private var document = TextInputDocument()
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var inputState: DSTextInputState?
    @State private var highlighted = 0
    @State private var dismissed = false

    private var completions: [ComposerFieldCompletion] {
        guard !dismissed, isFocused, let query = inputState?.query else { return [] }
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
            onSubmit: actions.send, onKey: handleKey, onAttachments: onAttachments,
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

#if DEBUG
import SwiftUI

enum ComposerBaselineFixtures {
    static func field(
        _ text: String = "", width: CGFloat = DS.ComposerField.previewWidth,
        attachments: Bool = false, working: Bool = false, stopping: Bool = false
    ) -> some View {
        var state = ComposerRowPreviewFixtures.state
        state.isWorking = working
        state.isStopping = stopping
        if working { state.locations = [] }
        state.disabledReason = text.isEmpty && !attachments ? "Write a message or attach a file" : nil
        return ComposerFieldBaseline(
            text: .constant(text), isFocused: .constant(false), openMenu: .constant(nil), state: state,
            actions: .init()
        ) {
            if attachments {
                FlowLayout(spacing: DS.Space.sm) {
                    ComposerChip("ComposerField.swift", systemImage: "doc.text") {}
                    ComposerChip("Layout.png", systemImage: "photo") {}
                    ComposerChip("Comment: keep the row in place", systemImage: "text.bubble") {}
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.md)
            }
        }
        .frame(width: width)
    }
}

#Preview("Composer field - Empty, draft, attachments and growing text") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            ComposerBaselineFixtures.field()
            ComposerBaselineFixtures.field("Keep the message field calm and the controls close together.")
            ComposerBaselineFixtures.field("Review the attached layout and comment.", attachments: true)
            ComposerBaselineFixtures.field(
                (1...12).map { "Line \($0): text grows upward, then scrolls after ten lines." }.joined(separator: "\n"))
        }
    }
}

#Preview("Composer field - Narrow, working and labelled stopping") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            ComposerBaselineFixtures.field("A narrow new task", width: DS.ComposerField.narrowWidth)
            ComposerBaselineFixtures.field("A follow-up waits in the queue", working: true)
            ComposerBaselineFixtures.field("Keep this draft when stopped", working: true, stopping: true)
        }
    }
}

#Preview("Composer field - File and command lists") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            ComposerFieldSuggestions(
                items: [
                    .file("./"), .file("native/"), .file("native/Composer/"),
                    .file("native/Composer/ComposerField.swift"),
                ],
                highlighted: .constant(2), choose: { _ in })
            ComposerFieldSuggestions(
                items: [
                    .command(.init(native: "goal", description: "Manage the task goal")),
                    .command(.init(native: "plan", description: "Plan the next change")),
                    .command(.init(native: "compact", description: "Compact the conversation")),
                ],
                highlighted: .constant(0), choose: { _ in })
        }
        .frame(width: DS.ComposerField.completionWidth)
    }
}

#Preview("Composer field - Attachment failure") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.sm) {
            NoticeBanner(tone: .warning, title: "Couldn't attach Layout.png. Try attaching it with Attach Files.")
            ComposerBaselineFixtures.field("Review the layout once I attach it.")
        }
        .frame(width: DS.ComposerField.previewWidth)
    }
}

#Preview("Composer field - Completion above the caret") {
    ComposerSinglePreview {
        VStack(spacing: 0) {
            Spacer(minLength: ComposerMetrics.suggestionListMaxHeight)
            ComposerFieldBaseline(
                text: .constant("Review @./"), isFocused: .constant(true), openMenu: .constant(nil),
                state: ComposerRowPreviewFixtures.state, actions: .init(),
                files: ["native/", "docs/", "Packages/", "README.md"]
            ) { EmptyView() }
        }
        .frame(width: DS.ComposerField.previewWidth)
    }
}
#endif

private struct ComposerSinglePreview<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.padding(DS.Space.xl).background(.dsBackground).fixedSize() }
}
