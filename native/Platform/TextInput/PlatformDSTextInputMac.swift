#if canImport(AppKit)
import AppKit
import SwiftUI
#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif

struct PlatformDSTextInput: NSViewRepresentable {
    let input: DSTextInput

    func makeNSView(context: Context) -> PlatformDSTextInputScroll {
        let scroll = PlatformDSTextInputScroll()
        scroll.scroll.drawsBackground = false
        scroll.scroll.hasHorizontalScroller = false
        scroll.scroll.hasVerticalScroller = false
        scroll.scroll.autohidesScrollers = true
        let editor = PlatformDSTextInputMacView()
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainerInset = .zero
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isContinuousSpellCheckingEnabled = true
        editor.registerForDraggedTypes([.fileURL, .png, .tiff, .init("public.jpeg")])
        editor.delegate = context.coordinator
        scroll.documentView = editor
        editor.changed = { [weak scroll] in
            scroll?.invalidateIntrinsicContentSize()
            scroll?.needsLayout = true
        }
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: PlatformDSTextInputScroll, context: Context) {
        guard let editor = scroll.documentView as? PlatformDSTextInputMacView else { return }
        context.coordinator.input = input
        editor.input = input
        editor.style = PlatformDSTextInputStyle(environment: context.environment)
        scroll.maximumLines = max(1, input.maximumLines)
        editor.insertionPointColor = editor.style?.accent ?? .textColor
        editor.setAccessibilityLabel(input.accessibilityLabel)
        if !editor.hasMarkedText(), let storage = editor.textStorage, let style = editor.style {
            editor.font = style.font
            editor.textColor = style.foreground
            editor.typingAttributes = style.attributes
            let changed = PlatformDSTextInputStyle.document(storage) != input.document
            if changed {
                editor.replaceDocument(input.document, selection: input.selection?.wrappedValue)
            } else if context.coordinator.previousStyle != editor.style {
                let selection = editor.selectedRange()
                storage.setAttributedString(style.attributed(input.document))
                editor.setSelectedRange(selection)
            }
            if let selected = input.selection?.wrappedValue,
                selected != context.coordinator.lastBoundSelection,
                Range(selected, in: editor.string) != nil
            {
                context.coordinator.lastBoundSelection = selected
                editor.setSelectedRange(selected)
            }
            context.coordinator.previousStyle = style
        }
        if let focused = input.isFocused?.wrappedValue, let window = editor.window {
            if focused, window.firstResponder !== editor { window.makeFirstResponder(editor) }
            if !focused, window.firstResponder === editor { window.makeFirstResponder(nil) }
        }
        editor.needsDisplay = true
        editor.changed?()
        context.coordinator.publish(editor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlatformDSTextInputScroll, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.measure(width: width))
    }

    func makeCoordinator() -> Coordinator { Coordinator(input: input) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var input: DSTextInput
        var previousStyle: PlatformDSTextInputStyle?
        var lastBoundSelection: NSRange?
        private var lastState: DSTextInputState?
        init(input: DSTextInput) { self.input = input }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? PlatformDSTextInputMacView, let storage = editor.textStorage
            else { return }
            let document = PlatformDSTextInputStyle.document(storage)
            if input.document != document { input.document = document }
            if !editor.hasMarkedText() { editor.typingAttributes = editor.style?.attributes ?? [:] }
            editor.changed?()
            publish(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? PlatformDSTextInputMacView else { return }
            publish(editor)
        }

        func publish(_ editor: PlatformDSTextInputMacView) {
            let selection = editor.selectedRange()
            let composing = editor.hasMarkedText()
            var caret = CGRect.zero
            if let window = editor.window, let scroll = editor.enclosingScrollView {
                let screen = editor.firstRect(
                    forCharacterRange: NSRange(location: selection.location, length: 0), actualRange: nil)
                caret = scroll.superview?.convert(window.convertFromScreen(screen), from: nil) ?? .zero
            }
            let state = DSTextInputState(
                selection: selection, caret: caret,
                query: TextInputQuery(document: input.document, selection: selection, isComposing: composing),
                isComposing: composing)
            guard state != lastState else { return }
            lastState = state
            // Native selection notifications may arrive inside SwiftUI's update/layout transaction.
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

final class PlatformDSTextInputScroll: NSView {
    let scroll = PlatformDSTextInputViewport()
    var documentView: NSView? {
        get { scroll.documentView }
        set { scroll.documentView = newValue }
    }
    override init(frame: NSRect) { super.init(frame: frame); addSubview(scroll) }
    required init?(coder: NSCoder) { nil }
    var maximumLines = 10
    private var lastHeight: CGFloat = 0
    private var deliveredHeight: CGFloat = 0
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measure(width: bounds.width))
    }
    func measure(width: CGFloat) -> CGFloat {
        guard width > 0, let editor = documentView as? PlatformDSTextInputMacView,
            let manager = editor.layoutManager, let container = editor.textContainer, let style = editor.style
        else { return lastHeight }
        container.containerSize = CGSize(
            width: max(1, width - DS.TextInput.inset * 2), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let content = max(style.lineHeight, manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)
        let height = ceil(min(content, style.lineHeight * CGFloat(maximumLines)) + DS.TextInput.inset * 2)
        let editorSize = CGSize(width: max(1, width - DS.TextInput.inset * 2), height: content)
        if editor.frame.size != editorSize { editor.setFrameSize(editorSize) }
        if lastHeight != height {
            lastHeight = height
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, self.lastHeight == height, self.deliveredHeight != height else { return }
                self.deliveredHeight = height
                editor?.input?.onHeightChange(height)
            }
        }
        return height
    }
    override func layout() {
        super.layout()
        scroll.frame = bounds.insetBy(dx: DS.TextInput.inset, dy: DS.TextInput.inset)
        _ = measure(width: bounds.width)
        if let editor = documentView as? PlatformDSTextInputMacView,
            let coordinator = editor.delegate as? PlatformDSTextInput.Coordinator
        {
            coordinator.publish(editor)
        }
    }
}

final class PlatformDSTextInputViewport: NSScrollView {
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        if let editor = documentView as? PlatformDSTextInputMacView,
            let coordinator = editor.delegate as? PlatformDSTextInput.Coordinator
        {
            coordinator.publish(editor)
        }
    }
}

final class PlatformDSTextInputMacView: NSTextView {
    var input: DSTextInput?
    var style: PlatformDSTextInputStyle?
    var changed: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, input?.isFocused?.wrappedValue == false { input?.isFocused?.wrappedValue = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, input?.isFocused?.wrappedValue == true { input?.isFocused?.wrappedValue = false }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if input?.isFocused?.wrappedValue == true { window?.makeFirstResponder(self) }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "dsTextInputFixture") { PlatformDSTextInputChecks.editor = self }
        #endif
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let input, let style {
            var attributes = style.attributes
            attributes[.foregroundColor] = style.secondary
            NSAttributedString(string: input.placeholder, attributes: attributes)
                .draw(at: textContainerOrigin)
        }
    }

    override func accessibilityValue() -> String? {
        textStorage.map { PlatformDSTextInputStyle.document($0).plainText } ?? ""
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText() {
            let key: DSTextInputKey? =
                switch event.keyCode {
                case 36, 76: .submit
                case 126: .up
                case 125: .down
                case 53: .escape
                case 48: .tab
                default: nil
                }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let key, modifiers.isDisjoint(with: [.command, .control, .option, .shift]), input?.onKey(key) == true {
                return
            }
            if key == .submit, !modifiers.intersection([.shift, .option]).isEmpty {
                insertText("\n", replacementRange: selectedRange())
                return
            }
            if key == .submit, modifiers.isDisjoint(with: [.shift, .option, .control]) {
                input?.onSubmit()
                return
            }
        }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(sender) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }

    func replaceDocument(_ document: TextInputDocument, selection: NSRange? = nil) {
        guard let storage = textStorage, let style else { return }
        let old = PlatformDSTextInputStyle.document(storage)
        let oldSelection = selectedRange()
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.replaceDocument(old, selection: oldSelection) }
        }
        storage.setAttributedString(style.attributed(document))
        setSelectedRange(
            selection.flatMap { Range($0, in: string) != nil ? $0 : nil }
                ?? NSRange(location: storage.length, length: 0))
        didChangeText()
    }

    override func copy(_ sender: Any?) { copyPlainText() }
    override func cut(_ sender: Any?) {
        copyPlainText()
        insertText("", replacementRange: selectedRange())
    }
    private func copyPlainText() {
        guard let storage = textStorage,
            let slice = PlatformDSTextInputStyle.document(storage).slice(selectedRange())
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(slice.plainText, forType: .string)
    }
    override func paste(_ sender: Any?) {
        if receiveAttachments(NSPasteboard.general) { return }
        if let text = NSPasteboard.general.string(forType: .string) {
            insertText(text, replacementRange: selectedRange())
        }
    }
    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
    override func pasteAsRichText(_ sender: Any?) { paste(sender) }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        hasAttachments(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        hasAttachments(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        hasAttachments(sender.draggingPasteboard) || super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if receiveAttachments(sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }
    private func hasAttachments(_ board: NSPasteboard) -> Bool {
        board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || board.availableType(from: [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]) != nil
    }
    @discardableResult func receiveAttachments(_ board: NSPasteboard) -> Bool {
        let urls =
            (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { input?.onAttachments(urls.map { .file($0) }); return true }
        for type in [NSPasteboard.PasteboardType.png, .tiff, .init("public.jpeg")] {
            if let data = board.data(forType: type) {
                input?.onAttachments([.image(data, contentType: type.rawValue)]); return true
            }
        }
        return false
    }
}
#endif
