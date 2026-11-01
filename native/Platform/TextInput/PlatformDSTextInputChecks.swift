import SwiftUI

#if DEBUG
#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif
#if canImport(AppKit)
import AppKit

/// Runs only on the isolated fixture. It drives the real text view without changing input sources
/// or the general clipboard. Assertions exercise NSTextInputClient's marked-text protocol directly.
enum PlatformDSTextInputChecks {
    static weak var editor: PlatformDSTextInputMacView?

    static func run() -> String {
        guard let editor, let scroll = editor.enclosingScrollView?.superview as? PlatformDSTextInputScroll else {
            return "Checks failed: no editor"
        }
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) { if !condition { failures.append(name) } }
        let original = editor.input
        var document = TextInputDocument()
        var submitted = 0
        var keys: [DSTextInputKey] = []
        var attachments = 0
        editor.input = DSTextInput(
            document: Binding(get: { document }, set: { document = $0 }),
            onSubmit: { submitted += 1 },
            onKey: {
                keys.append($0); return false
            },
            onAttachments: { attachments += $0.count })
        defer {
            editor.input = original
            editor.replaceDocument(.init())
        }
        editor.replaceDocument(.init())
        let oneLine = scroll.measure(width: 320)
        editor.insertText("literal -- \"quotes\"", replacementRange: editor.selectedRange())
        check(editor.string == "literal -- \"quotes\"", "literal typing")
        editor.replaceDocument(.init("First\n"))
        check(scroll.measure(width: 320) > oneLine, "trailing newline height")
        editor.replaceDocument(.init((1...14).map { "Line \($0)" }.joined(separator: "\n")))
        let capped = scroll.measure(width: 320)
        check(capped == ceil((editor.style?.lineHeight ?? 0) * 10 + DS.TextInput.inset * 2), "height cap")
        check(scroll.measure(width: 320) == capped, "stable layout")
        editor.replaceDocument(.init(runs: [.text("Read "), .mention(path: "Sources/App.swift")]))
        editor.undoManager?.removeAllActions()
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        editor.deleteBackward(nil)
        check(editor.string == "Read ", "atomic token deletion")
        editor.undoManager?.undo()
        check(
            editor.textStorage.map { PlatformDSTextInputStyle.document($0).plainText } == "Read @Sources/App.swift",
            "token undo")
        editor.undoManager?.redo()
        check(editor.string == "Read ", "token redo")
        editor.replaceDocument(.init())
        editor.setMarkedText(
            "にほん", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        check(editor.hasMarkedText(), "Japanese marked text")
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: editor.window?.windowNumber ?? 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        {
            editor.keyDown(with: event)
        }
        check(submitted == 0 && keys.isEmpty, "IME owns Return")
        // Return is interpreted by the active input engine. Test Japanese candidate replacement
        // in its own composition rather than assuming that engine leaves the marked range open.
        editor.unmarkText()
        editor.replaceDocument(.init())
        editor.setMarkedText(
            "にほん", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        // Model the input method replacing its marked range with the chosen candidate.
        editor.insertText("日本", replacementRange: editor.markedRange())
        editor.unmarkText()
        check(!editor.hasMarkedText() && editor.string == "日本", "Japanese commit")
        check(editor.accessibilityValue() == "日本", "accessibility value")
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: editor.window?.windowNumber ?? 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        {
            editor.keyDown(with: event)
        }
        check(submitted == 1 && editor.string == "日本", "Return submits")
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
            windowNumber: editor.window?.windowNumber ?? 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        {
            editor.keyDown(with: event)
        }
        check(editor.string == "日本\n" && submitted == 1, "Shift-Return newline")
        keys.removeAll()
        editor.input?.onKey = {
            keys.append($0); return true
        }
        for code: UInt16 in [126, 125, 53, 48, 36] {
            if let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: editor.window?.windowNumber ?? 0, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)
            {
                editor.keyDown(with: event)
            }
        }
        check(keys == [.up, .down, .escape, .tab, .submit] && submitted == 1, "suggestion key hooks")
        // A private pasteboard cannot touch the person's clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([URL(fileURLWithPath: "/tmp/fixture.png") as NSURL])
        let before = editor.string
        check(editor.receiveAttachments(board), "file paste")
        board.clearContents()
        board.setData(Data([0, 1]), forType: .png)
        check(editor.receiveAttachments(board), "image paste")
        check(editor.registeredDraggedTypes.contains(.init("public.jpeg")), "JPEG drop registration")
        check(attachments == 2 && editor.string == before, "attachments do not type paths")
        return failures.isEmpty
            ? "Checks passed: editing, sizing, tokens, undo, IME, keys, attachments, accessibility"
            : "Checks failed: " + failures.joined(separator: ", ")
    }
}

struct PlatformDSTextInputFixture: View {
    @State private var document = TextInputDocument()
    @State private var submitted = 0
    @State private var result = "Ready"
    @State private var inputState: DSTextInputState?
    @State private var inputHeight: CGFloat = 0
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var focused = true
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DSTextInput(
                document: $document, isFocused: $focused, selection: $selection, onSubmit: { submitted += 1 },
                onStateChange: { inputState = $0 }, onHeightChange: { inputHeight = $0 }
            )
            .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsBorder) }
            Button("Run input checks") { result = PlatformDSTextInputChecks.run() }
            Button("Focus input") { focused = true }
            Text(result).accessibilityIdentifier("text-input-check-result")
            Text("Submitted: \(submitted)")
            Text(
                "Query: \(inputState?.query?.text ?? "none") · Caret: \(selection.location) · Height: \(Int(inputHeight))"
            )
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextPrimary)
        .padding(DS.Space.xl)
        .frame(width: DS.TextInput.fixtureWidth)
        .background(.dsBackground)
    }
}
#Preview("DSTextInput - Interactive checks") {
    DSPreviewPair { PlatformDSTextInputFixture() }
}
#endif
#endif

extension View {
    @ViewBuilder func dsTextInputCheckFixture() -> some View {
        #if DEBUG && canImport(AppKit)
        if UserDefaults.standard.bool(forKey: "dsTextInputFixture") { PlatformDSTextInputFixture() } else { self }
        #else
        self
        #endif
    }
}
