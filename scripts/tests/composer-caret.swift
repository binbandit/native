import AppKit
import SwiftUI

@testable import Native

/// Types into the real composer editor, in a window that's never shown, and checks the caret stays
/// where the typing happens, and that the rich-text editor (used once code appears) draws a draft
/// exactly like the plain one. `--render <folder>` also writes each editor's pixels there, so a
/// change to its line metrics can be diffed against the last build's.
@main
@MainActor
private struct ComposerCaretChecks {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let arguments = CommandLine.arguments
        let renderFolder = arguments.firstIndex(of: "--render").map { URL(fileURLWithPath: arguments[$0 + 1]) }
        var failures = 0

        for editor in ComposerCaretFixture.Editor.allCases {
            for draft in ["Plain draft without code", "Look at `PromptQueue` here"] {
                let fixture = ComposerCaretFixture(editor: editor, draft: draft)
                // Mid-draft, after "Look at " / "Plain dr".
                let caret = 8
                guard fixture.textView.string == draft else {
                    print("FAIL \(editor) [\(draft)]: the editor shows \(fixture.textView.string.debugDescription)")
                    failures += 1
                    continue
                }
                fixture.textView.setSelectedRange(NSRange(location: caret, length: 0))
                fixture.pump()
                for (step, character) in "abc".enumerated() {
                    fixture.type(character)
                    let location = fixture.textView.selectedRange().location
                    if location != caret + step + 1 {
                        print(
                            "FAIL \(editor) [\(draft)]: after typing \(character) the caret is at \(location), "
                                + "not \(caret + step + 1) (\(fixture.textView.string.debugDescription))")
                        failures += 1
                        break
                    }
                }
                let expected = draft.prefix(caret) + "abc" + draft.dropFirst(caret)
                if fixture.text != String(expected) {
                    print("FAIL \(editor) [\(draft)]: the draft is \(fixture.text.debugDescription)")
                    failures += 1
                }
            }
        }

        for editor in ComposerCaretFixture.Editor.allCases {
            let draft = "The queue test still flakes when two prompts are\nqueued at once.\n\nLook at the ordering."
            for dark in [false, true] {
                let plain = ComposerCaretFixture(editor: editor, draft: draft, dark: dark, focused: false)
                // A backtick moves the editor to rich text for good, so the same draft then shows there.
                let rich = ComposerCaretFixture(editor: editor, draft: "`", dark: dark, focused: false)
                rich.model.text = draft
                rich.pump()
                if try plain.png() != rich.png() {
                    print("FAIL \(editor) \(dark ? "dark" : "light"): the rich-text editor draws lines differently")
                    failures += 1
                }
            }
        }

        if let renderFolder {
            try FileManager.default.createDirectory(at: renderFolder, withIntermediateDirectories: true)
            for editor in ComposerCaretFixture.Editor.allCases {
                for (name, draft) in ComposerCaretFixture.renderDrafts {
                    for dark in [false, true] {
                        let fixture = ComposerCaretFixture(editor: editor, draft: draft, dark: dark, focused: false)
                        let file = renderFolder.appending(path: "\(editor)-\(name)-\(dark ? "dark" : "light").png")
                        try fixture.png().write(to: file)
                    }
                }
            }
            print("Rendered into \(renderFolder.path)")
        }

        if failures > 0 {
            print("\(failures) composer caret check(s) failed")
            exit(1)
        }
        print("Composer caret checks passed")
    }
}

/// One editor in an offscreen window, with its draft and selection held the way the composer holds
/// them.
@MainActor
private final class ComposerCaretFixture {
    /// The three places the editor is used, with their own font and line spacing.
    enum Editor: CaseIterable {
        case composer, composePage, quickEntry
    }

    static let renderDrafts = [
        ("plain", "The queue test still flakes when two prompts are\nqueued at once, so look at the ordering."),
        ("inline", "Look at `PromptQueueTests` and fix the `move(_:)`\nordering before the next nightly."),
        ("block", "Fix the ordering:\n\n```swift\nqueue.move(id, .up)\nqueue.flush()\n```\nThen rerun."),
    ]

    let window: NSWindow
    let model: ComposerCaretModel
    var text: String { model.text }

    init(editor: Editor, draft: String, dark: Bool = false, focused: Bool = true) {
        model = ComposerCaretModel(text: draft)
        let host = NSHostingView(rootView: ComposerCaretHost(model: model, editor: editor))
        window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 560, height: 220), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        pump()
        if focused { window.makeFirstResponder(textView) }
        pump()
    }

    var textView: NSTextView {
        func find(_ view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView { return textView }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let contentView = window.contentView, let textView = find(contentView) else {
            fatalError("The editor has no text view")
        }
        return textView
    }

    /// Lets SwiftUI apply pending updates in both directions.
    func pump() {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    /// A key press, through the window as AppKit delivers it.
    func type(_ character: Character) {
        let characters = String(character)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)
            else { continue }
            window.sendEvent(event)
        }
        pump()
    }

    func png() throws -> Data {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

@MainActor
@Observable
private final class ComposerCaretModel {
    var text: String
    init(text: String) { self.text = text }
}

private struct ComposerCaretHost: View {
    @Bindable var model: ComposerCaretModel
    let editor: ComposerCaretFixture.Editor
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            switch editor {
            case .composer:
                ComposerEditor(text: $model.text, selection: $selection, placeholder: "", isFocused: $isFocused) { _ in
                    .ignored
                }
            case .composePage:
                ComposerEditor(
                    text: $model.text, selection: $selection, placeholder: "", isFocused: $isFocused,
                    font: DS.ComposeTask.editorFont, lineSpacing: DS.ComposeTask.editorLineSpacing,
                    richLineLeading: DS.ComposeTask.editorRichLineLeading,
                    insets: DS.ComposeTask.editorInsets, maximumHeight: DS.ComposeTask.editorMaxHeight
                ) { _ in .ignored }
            case .quickEntry:
                ComposerEditor(
                    text: $model.text, selection: $selection, placeholder: "", isFocused: $isFocused,
                    font: DS.QuickEntry.editorFont, lineSpacing: DS.QuickEntry.editorLineSpacing,
                    richLineLeading: DS.QuickEntry.editorRichLineLeading, insets: DS.QuickEntry.textInsets
                ) { _ in .ignored }
            }
        }
        .frame(width: 560, height: 220, alignment: .top)
        .background(Color.dsBackground)
    }
}
