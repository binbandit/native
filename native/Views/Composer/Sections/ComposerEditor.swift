import ACP
import CoreText
import SwiftUI

/// The composer's text field: 13pt text that grows with the draft to a cap, then scrolls. Keys go
/// to `onKey` first, so the composer can send, recall and drive its lists.
///
/// Code in the draft (`PromptCode.runs`) shows in the code font, restyled as it's typed: a fenced
/// block with its fence lines dimmed, an inline span on a quiet fill. Blocks get no fill, which a
/// text view can only draw behind each line's text, leaving a ragged edge. Only the look changes:
/// the draft is exactly what was typed or pasted, and anything pasted text brought along (fonts,
/// colors, links) is dropped.
///
/// Styling needs SwiftUI's rich-text editor, which leaks its text storage every time it's torn down
/// (its `NSSwiftMutableAttributedString` and that string's proxy keep each other alive), and every
/// task switch tears the composer down. So a draft without code uses the plain editor, and an editor
/// switches to rich text, for good, once code may appear in it.
struct ComposerEditor: View {
    @Binding var text: String
    /// Where the cursor is, for `@` mentions in the middle of the draft.
    @Binding var selection: TextSelection?
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    /// While an attachment chip is selected the keys are its, so the caret steps aside.
    var hidesCaret = false
    var font: Font = .dsCallout
    var lineSpacing: CGFloat = ComposerMetrics.editorLineSpacing
    var insets: EdgeInsets = DS.Composer.textInsets
    let onKey: (KeyPress) -> KeyPress.Result

    /// Whether the rich-text editor is in use, from the first backtick or `~~~` on.
    @State private var showsCode = false
    /// The editor had focus when it switched to rich text, so the new one takes it.
    @State private var refocusRichEditor = false
    /// The draft as the rich-text editor holds it: `text`'s characters, with code styled.
    @State private var styled = AttributedString()
    @State private var styledSelection = AttributedTextSelection()
    /// The selection both sides last agreed on, as UTF-8 offsets, so a change to `text` from outside
    /// can tell whether a new selection came with it.
    @State private var syncedSelection: Range<Int>?
    @Environment(\.dsCodeFont) private var codeFont

    var body: some View {
        // TextEditor doesn't size to its content, so a hidden copy of the text sets the height and the
        // editor fills it, scrolling once the cap is reached.
        Text(sizingText)
            .font(font)
            .lineSpacing(lineSpacing)
            .padding(.horizontal, ComposerMetrics.editorLineFragmentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: ComposerMetrics.editorMaxHeight, alignment: .top)
            // Size to the text (capped) rather than to whatever height is on offer.
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .overlay {
                Group {
                    if showsCode {
                        TextEditor(text: $styled, selection: $styledSelection)
                            .onAppear {
                                if refocusRichEditor {
                                    refocusRichEditor = false
                                    isFocused.wrappedValue = true
                                }
                            }
                    } else {
                        TextEditor(text: $text, selection: $selection)
                    }
                }
                .font(font)
                .lineSpacing(lineSpacing)
                .foregroundStyle(.dsTextPrimary)
                // The window's tint (`dsAccentPalette`) colors the caret; nil would reset it to blue.
                .tint(hidesCaret ? .clear : .dsAccent)
                .textEditorStyle(.plain)
                .scrollIndicators(.never)
                .focused(isFocused)
                .onKeyPress(phases: [.down, .repeat], action: onKey)
                .accessibilityLabel("Message")
                // Files and images dropped on the text attach instead (the composer's drop area).
                .textViewTakesOnlyTextDrops()
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(font)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.leading, ComposerMetrics.editorLineFragmentPadding)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, insets.leading - ComposerMetrics.editorLineFragmentPadding)
            .padding(.trailing, insets.trailing - ComposerMetrics.editorLineFragmentPadding)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .onAppear(perform: textChangedOutside)
            .onChange(of: styled, editorChanged)
            .onChange(of: styledSelection, editorSelectionChanged)
            .onChange(of: text, textChangedOutside)
            .onChange(of: selection, textChangedOutside)
            .onChange(of: codeFont) { restyle() }
    }

    /// Whether `text` may hold code: a backtick or a tilde fence.
    private static func mayHaveCode(_ text: String) -> Bool {
        text.contains("`") || text.contains("~~~")
    }

    /// Moves the draft, the selection and focus over to the rich-text editor.
    private func switchToRichText() {
        styled = styledString(text)
        let end = text.utf8.count
        select(Self.offsets(of: selection, in: text) ?? end..<end)
        refocusRichEditor = isFocused.wrappedValue
        showsCode = true
    }

    /// The text for sizing, with a space after a trailing line break so the empty last line counts.
    private var sizingText: AttributedString {
        var sizing = styledString(text)
        if text.isEmpty || text.hasSuffix("\n") {
            sizing.append(AttributedString(" "))
        }
        return sizing
    }

    // MARK: - Keeping the two in step

    /// Typing, pasting or moving the caret in the editor: the draft and selection follow, and code is
    /// restyled.
    private func editorChanged() {
        let typed = String(styled.characters)
        if typed != text {
            text = typed
        }
        restyle()
        editorSelectionChanged()
    }

    private func editorSelectionChanged() {
        guard String(styled.characters) == text, let offsets = editorSelection else { return }
        syncedSelection = offsets
        if offsets != Self.offsets(of: selection, in: text) {
            selection = Self.textSelection(offsets, in: text)
        }
    }

    /// The composer changed the draft or the selection itself (a completion, a recalled prompt, a
    /// code edit). A new draft without a new selection puts the caret at its end.
    private func textChangedOutside() {
        // The plain editor is bound to the draft itself, until code may appear.
        guard showsCode else {
            if Self.mayHaveCode(text) {
                switchToRichText()
            }
            return
        }
        let wanted = Self.offsets(of: selection, in: text)
        if String(styled.characters) != text {
            styled = styledString(text)
            let end = text.utf8.count
            let caret = wanted.flatMap { $0 == syncedSelection ? nil : $0 } ?? end..<end
            select(caret)
        } else if let wanted, wanted != editorSelection {
            select(wanted)
        }
    }

    private func select(_ offsets: Range<Int>) {
        let lower = styled.utf8.index(styled.startIndex, offsetBy: offsets.lowerBound)
        let upper = styled.utf8.index(styled.startIndex, offsetBy: offsets.upperBound)
        styledSelection =
            offsets.isEmpty
            ? AttributedTextSelection(insertionPoint: lower) : AttributedTextSelection(range: lower..<upper)
        syncedSelection = offsets
    }

    /// The editor's selection as UTF-8 offsets into its text.
    private var editorSelection: Range<Int>? {
        let offset = { (index: AttributedString.Index) in
            self.styled.utf8.distance(from: self.styled.startIndex, to: index)
        }
        switch styledSelection.indices(in: styled) {
        case .insertionPoint(let index):
            return offset(index)..<offset(index)
        case .ranges(let ranges):
            return ranges.ranges.first.map { offset($0.lowerBound)..<offset($0.upperBound) }
        }
    }

    private static func offsets(of selection: TextSelection?, in text: String) -> Range<Int>? {
        guard case .selection(let range)? = selection?.indices, range.upperBound <= text.endIndex else { return nil }
        return text.utf8.distance(
            from: text.startIndex, to: range.lowerBound)..<text.utf8.distance(
                from: text.startIndex, to: range.upperBound)
    }

    private static func textSelection(_ offsets: Range<Int>, in text: String) -> TextSelection {
        let lower = text.utf8.index(text.startIndex, offsetBy: offsets.lowerBound)
        let upper = text.utf8.index(text.startIndex, offsetBy: offsets.upperBound)
        return offsets.isEmpty ? TextSelection(insertionPoint: lower) : TextSelection(range: lower..<upper)
    }

    // MARK: - Styling

    /// `text` with its code styled.
    private func styledString(_ text: String) -> AttributedString {
        var styled = AttributedString(text)
        applyCodeStyle(to: &styled, from: text)
        return styled
    }

    /// Restyles the editor's text in place, keeping the selection where it is. Nothing changes when
    /// the styling already fits, which is most keystrokes.
    private func restyle() {
        guard showsCode else { return }
        let typed = String(styled.characters)
        guard styled != styledString(typed) else { return }
        styled.transform(updating: &styledSelection) { styled in
            styled[styled.startIndex..<styled.endIndex].setAttributes(AttributeContainer())
            applyCodeStyle(to: &styled, from: typed)
        }
    }

    private func applyCodeStyle(to styled: inout AttributedString, from text: String) {
        var code = AttributeContainer()
        code.font = Font(codeFont.platformFont(offset: DSCodeTextRole.block.sizeOffset) as CTFont)
        var fence = AttributeContainer()
        fence.foregroundColor = .dsTextSecondary
        var inline = code
        inline.backgroundColor = .dsFill
        for run in PromptCode.runs(in: text) {
            let lower = styled.utf8.index(
                styled.startIndex, offsetBy: text.utf8.distance(from: text.startIndex, to: run.range.lowerBound))
            let upper = styled.utf8.index(
                styled.startIndex, offsetBy: text.utf8.distance(from: text.startIndex, to: run.range.upperBound))
            switch run.kind {
            case .block: styled[lower..<upper].mergeAttributes(code)
            case .fence: styled[lower..<upper].mergeAttributes(fence)
            case .inline: styled[lower..<upper].mergeAttributes(inline)
            }
        }
    }
}

#if DEBUG
#Preview("Editor") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerSurface {
                ComposerEditorPreview(text: "", placeholder: "What should Claude Code work on?")
            }
            ComposerSurface {
                ComposerEditorPreview(
                    text: """
                        The queue test still flakes. Look at `PromptQueueTests` and fix the ordering:

                        ```swift
                        queue.move(id, .up)
                        ```
                        """,
                    placeholder: "")
            }
        }
        .frame(width: 560)
    }
}

/// Holds the editor's text, selection and focus, which a preview can't pass as plain values.
private struct ComposerEditorPreview: View {
    @State var text: String
    let placeholder: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        ComposerEditor(text: $text, selection: $selection, placeholder: placeholder, isFocused: $isFocused) { _ in
            .ignored
        }
    }
}
#endif
