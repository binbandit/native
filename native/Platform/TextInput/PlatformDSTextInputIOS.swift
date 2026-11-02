#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif

struct PlatformDSTextInput: UIViewRepresentable {
    let input: DSTextInput

    func makeUIView(context: Context) -> PlatformDSTextInputIOSContainer {
        let container = PlatformDSTextInputIOSContainer()
        let editor = PlatformDSTextInputIOSView(usingTextLayoutManager: false)
        editor.delegate = context.coordinator
        editor.backgroundColor = .clear
        editor.textContainerInset = .zero
        editor.textContainer.lineFragmentPadding = 0
        editor.smartDashesType = .no
        editor.smartQuotesType = .no
        editor.smartInsertDeleteType = .no
        editor.autocorrectionType = .no
        editor.spellCheckingType = .yes
        editor.autocapitalizationType = .none
        editor.inlinePredictionType = .no
        editor.textDropDelegate = editor
        editor.addInteraction(UIDropInteraction(delegate: editor))
        editor.showsVerticalScrollIndicator = false
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.editor = editor
        container.addSubview(editor)
        updateUIView(container, context: context)
        return container
    }

    func updateUIView(_ container: PlatformDSTextInputIOSContainer, context: Context) {
        guard let editor = container.editor else { return }
        context.coordinator.input = input
        editor.input = input
        editor.style = PlatformDSTextInputStyle(environment: context.environment)
        editor.isEditable = context.environment.isEnabled
        editor.tintColor = editor.style?.accent
        editor.accessibilityLabel = input.accessibilityLabel
        if editor.markedTextRange == nil, let style = editor.style {
            editor.font = style.font
            editor.textColor = style.foreground
            editor.typingAttributes = style.attributes
            let changed = PlatformDSTextInputStyle.document(editor.textStorage) != input.document
            if changed || context.coordinator.previousStyle != editor.style {
                let selected = editor.selectedRange
                if changed {
                    editor.replaceDocument(input.document, selection: input.selection?.wrappedValue)
                } else {
                    editor.textStorage.setAttributedString(style.attributed(input.document));
                    editor.selectedRange = selected
                }
            }
            if let selection = input.selection?.wrappedValue, Range(selection, in: editor.text) != nil,
                context.coordinator.lastBoundSelection != selection
            {
                context.coordinator.lastBoundSelection = selection
                editor.selectedRange = selection
            }
            context.coordinator.previousStyle = style
        }
        if let focused = input.isFocused?.wrappedValue, editor.window != nil {
            if focused, !editor.isFirstResponder { editor.becomeFirstResponder() }
            if !focused, editor.isFirstResponder { editor.resignFirstResponder() }
        }
        editor.invalidateIntrinsicContentSize()
        editor.setNeedsDisplay()
        context.coordinator.publish(editor)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: PlatformDSTextInputIOSContainer, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(
            width: width,
            height: (uiView.editor?.measure(width: width - DS.TextInput.inset * 2) ?? 0) + DS.TextInput.inset * 2)
    }
    func makeCoordinator() -> Coordinator { Coordinator(input: input) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var input: DSTextInput
        var previousStyle: PlatformDSTextInputStyle?
        var lastBoundSelection: NSRange?
        private var lastState: DSTextInputState?
        init(input: DSTextInput) { self.input = input }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard let editor = textView as? PlatformDSTextInputIOSView else { return true }
            if text == "\n", editor.markedTextRange == nil, !editor.literalNewline {
                if input.onEvent(.init(key: .return)) { return false }
                if input.onKey(.submit) != true { input.onSubmit() }
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let editor = textView as? PlatformDSTextInputIOSView else { return }
            let document = PlatformDSTextInputStyle.document(editor.textStorage)
            if input.document != document { input.document = document }
            if editor.markedTextRange == nil { editor.typingAttributes = editor.style?.attributes ?? [:] }
            editor.invalidateIntrinsicContentSize()
            editor.superview?.invalidateIntrinsicContentSize()
            editor.setNeedsDisplay()
            publish(editor)
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            if let editor = textView as? PlatformDSTextInputIOSView { publish(editor) }
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            if input.isFocused?.wrappedValue == false { input.isFocused?.wrappedValue = true }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            if input.isFocused?.wrappedValue == true { input.isFocused?.wrappedValue = false }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if let editor = scrollView as? PlatformDSTextInputIOSView { publish(editor) }
        }
        func publish(_ editor: PlatformDSTextInputIOSView) {
            let selection = editor.selectedRange
            let composing = editor.markedTextRange != nil
            let caret =
                editor.selectedTextRange.map { editor.convert(editor.caretRect(for: $0.end), to: editor.superview) }
                ?? .zero
            let state = DSTextInputState(
                selection: selection, caret: caret,
                query: TextInputQuery(document: input.document, selection: selection, isComposing: composing),
                isComposing: composing)
            guard lastState != state else { return }
            lastState = state
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastState == state else { return }
                if self.input.selection?.wrappedValue != selection {
                    self.lastBoundSelection = selection
                    self.input.selection?.wrappedValue = selection
                }
                self.input.onStateChange(state)
            }
        }
    }
}

final class PlatformDSTextInputIOSContainer: UIView {
    var editor: PlatformDSTextInputIOSView?
    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: (editor?.measure(width: bounds.width - DS.TextInput.inset * 2) ?? 0) + DS.TextInput.inset * 2)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        editor?.frame = bounds.insetBy(dx: DS.TextInput.inset, dy: DS.TextInput.inset)
    }
}

final class PlatformDSTextInputIOSView: UITextView, UIDropInteractionDelegate, UITextDropDelegate {
    var input: DSTextInput?
    var style: PlatformDSTextInputStyle?
    private var lastHeight: CGFloat = 0
    private var deliveredHeight: CGFloat = 0
    var literalNewline = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if input?.isFocused?.wrappedValue == true { becomeFirstResponder() }
    }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measure(width: bounds.width))
    }
    func measure(width: CGFloat) -> CGFloat {
        guard width > 0, let style else { return lastHeight }
        textContainer.size = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let content = max(
            style.lineHeight, layoutManager.usedRect(for: textContainer).maxY, layoutManager.extraLineFragmentRect.maxY)
        let cap = style.lineHeight * CGFloat(max(1, input?.maximumLines ?? 10))
        isScrollEnabled = content > cap
        let height = ceil(min(content, cap))
        if height != lastHeight {
            lastHeight = height
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastHeight == height, self.deliveredHeight != height else { return }
                self.deliveredHeight = height
                self.input?.onHeightChange(height + DS.TextInput.inset * 2)
            }
        }
        return height
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        (delegate as? PlatformDSTextInput.Coordinator)?.publish(self)
    }
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        if text.isEmpty, let input, let style {
            var attributes = style.attributes
            attributes[.foregroundColor] = style.secondary
            NSAttributedString(string: input.placeholder, attributes: attributes).draw(at: .zero)
        }
    }
    override var accessibilityValue: String? {
        get { PlatformDSTextInputStyle.document(textStorage).plainText }
        set { super.accessibilityValue = newValue }
    }
    override func insertText(_ text: String) {
        if text == "\n", markedTextRange == nil, !literalNewline {
            if input?.onEvent(.init(key: .return)) == true { return }
            if input?.onKey(.submit) != true { input?.onSubmit() }
            return
        }
        super.insertText(text)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard markedTextRange == nil, let key = presses.first?.key else {
            super.pressesBegan(presses, with: event); return
        }
        let equivalent: KeyEquivalent? =
            switch key.keyCode {
            case .keyboardReturnOrEnter, .keypadEnter: .return
            case .keyboardUpArrow: .upArrow
            case .keyboardDownArrow: .downArrow
            case .keyboardLeftArrow: .leftArrow
            case .keyboardRightArrow: .rightArrow
            case .keyboardDeleteOrBackspace: .delete
            case .keyboardDeleteForward: .deleteForward
            case .keyboardEscape: .escape
            case .keyboardTab: .tab
            default: nil
            }
        if let equivalent {
            var modifiers: EventModifiers = []
            if key.modifierFlags.contains(.command) { modifiers.insert(.command) }
            if key.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if key.modifierFlags.contains(.alternate) { modifiers.insert(.option) }
            if key.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            if input?.onEvent(.init(key: equivalent, modifiers: modifiers)) == true { return }
        }
        let action: DSTextInputKey? =
            switch key.keyCode {
            case .keyboardReturnOrEnter, .keypadEnter: .submit
            case .keyboardUpArrow: .up
            case .keyboardDownArrow: .down
            case .keyboardEscape: .escape
            case .keyboardTab: .tab
            default: nil
            }
        if key.modifierFlags.isEmpty, let action, input?.onKey(action) == true { return }
        if action == .submit, !key.modifierFlags.intersection([.shift, .alternate]).isEmpty {
            literalNewline = true
            super.insertText("\n")
            literalNewline = false
            return
        }
        if action == .submit, !key.modifierFlags.contains(.control) {
            input?.onSubmit()
            return
        }
        super.pressesBegan(presses, with: event)
    }
    func replaceDocument(_ document: TextInputDocument, selection: NSRange? = nil) {
        guard let style else { return }
        let old = PlatformDSTextInputStyle.document(textStorage)
        let oldSelection = selectedRange
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.replaceDocument(old, selection: oldSelection) }
        }
        textStorage.setAttributedString(style.attributed(document))
        selectedRange =
            selection.flatMap { Range($0, in: text) != nil ? $0 : nil }
            ?? NSRange(location: textStorage.length, length: 0)
        delegate?.textViewDidChange?(self)
    }

    override func copy(_ sender: Any?) {
        if let slice = PlatformDSTextInputStyle.document(textStorage).slice(selectedRange) {
            UIPasteboard.general.string = slice.plainText
        }
    }
    override func cut(_ sender: Any?) { copy(sender); super.insertText("") }
    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        let urls = (board.urls ?? []).filter(\.isFileURL)
        if !urls.isEmpty { input?.onAttachments(urls.map { .file($0) }); return }
        for type in [UTType.png, .jpeg, .tiff] {
            if let data = board.data(forPasteboardType: type.identifier) {
                input?.onAttachments([.image(data, contentType: type.identifier)]); return
            }
        }
        if let text = board.string {
            literalNewline = true
            super.insertText(text)
            literalNewline = false
        }
    }
    private func isAttachment(_ provider: NSItemProvider) -> Bool {
        TextInputDropProvider.representation(of: provider) != nil
    }
    func textDroppableView(
        _ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest
    ) -> UITextDropProposal {
        UITextDropProposal(
            operation: drop.dropSession.items.contains { isAttachment($0.itemProvider) } ? .cancel : .copy)
    }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.items.contains { isAttachment($0.itemProvider) }
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        for item in session.items {
            let provider = item.itemProvider
            guard let representation = TextInputDropProvider.representation(of: provider) else { continue }
            if case .document(let type) = representation {
                Task { @MainActor [weak self] in
                    guard let url = try? await TextInputDropProvider.loadFile(provider, type: type) else { return }
                    guard let self, let input = self.input else {
                        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                        return
                    }
                    input.onAttachments([.file(url)])
                }
                continue
            }
            let file = representation == .fileURL
            let type: String
            switch representation {
            case .fileURL: type = UTType.fileURL.identifier
            case .image(let imageType): type = imageType
            case .document: continue
            }
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor [weak self] in
                    if file, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                        self?.input?.onAttachments([.file(url)])
                    } else if !file {
                        self?.input?.onAttachments([.image(data, contentType: type)])
                    }
                }
            }
        }
    }
}
#endif
