import ACP
import AppKit
import Experiments
import Modes
import NativeAutomation
import SwiftUI
import TextInput

@testable import Native

/// No application launch, visible windows, key events, agent connections or general clipboard.
@main
private struct ComposerFieldInputRegression {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let fixture = try ComposerFieldInputFixture(root: root)
        defer { fixture.window.close() }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures.append(message) }
        }

        let editor = try fixture.editor()
        fixture.focus(editor)
        editor.insertText("A", replacementRange: editor.selectedRange())
        fixture.pump()
        check(fixture.window.firstResponder === editor, "typing one character keeps the first responder")
        check(editor.input?.isFocused?.wrappedValue == true, "native focus and composer focus agree after typing")
        editor.insertText("B", replacementRange: editor.selectedRange())
        fixture.pump()
        check(fixture.session.composerMessage == "AB", "successive native edits reach the session draft")

        editor.undoManager?.undo()
        fixture.pump()
        check(fixture.session.composerMessage.isEmpty, "native Undo removes the coalesced typing group")
        editor.undoManager?.redo()
        fixture.pump()
        check(fixture.session.composerMessage == "AB", "native Redo restores the draft")

        fixture.focus(editor)
        let beforePaste = fixture.session.composerMessage
        let file = root.appending(path: "fixtures/guide.txt")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setString(file.path, forType: .string)
        board.writeObjects([item])
        // The same private-pasteboard route as drive.sh paste-files, through the real paste monitor.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.native.debug.pasteAttachment"),
            object: String(ProcessInfo.processInfo.processIdentifier),
            userInfo: ["pasteboard": board.name.rawValue], deliverImmediately: true)
        fixture.wait { !fixture.session.attachments.isEmpty }
        check(fixture.session.attachments.count == 1, "private file paste reaches the session attachment handler")
        check(fixture.session.composerMessage == beforePaste, "file paste does not insert a path into the draft")

        fixture.reset(editor)
        editor.insertText("draft", replacementRange: editor.selectedRange())
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .leftArrow)) == true, "Left at the text start selects the attachment")
        fixture.pump()
        editor.insertText("x", replacementRange: editor.selectedRange())
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .delete)) == false, "typing returns Backspace to the editor")
        editor.deleteBackward(nil)
        fixture.pump()
        check(fixture.session.composerMessage == "draft", "Backspace removes the typed character")
        check(fixture.session.attachments.count == 1, "typing then Backspace keeps the attachment")

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .leftArrow)) == true, "Left selects the chip again")
        fixture.pump()
        // A native selection change uses the same delegate path as clicking back into the text.
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .delete)) == false, "moving the caret returns Backspace to the editor")
        check(fixture.session.attachments.count == 1, "moving the caret keeps the attachment")

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .leftArrow)) == true, "Left still selects a chip after a caret move")
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .rightArrow)) == true, "Right still returns from a chip to the text")

        fixture.reset(editor)
        editor.insertText("@", replacementRange: editor.selectedRange())
        fixture.pump()
        check(fixture.window.firstResponder === editor, "file trigger keeps focus")
        // Filtering also exercises query updates after the initial trigger starts the file index.
        editor.insertText("fixtures/gu", replacementRange: editor.selectedRange())
        fixture.pump()
        let acceptedFile = fixture.wait { editor.input?.onKey(.tab) == true }
        fixture.pump()
        check(acceptedFile, "file query loads matching suggestions and consumes Tab")
        check(fixture.session.composerMessage == "@fixtures/guide.txt ", "Tab accepts the indexed file")
        check(editor.string == "\u{FFFC} ", "file completion inserts an atomic mention")

        fixture.reset(editor)
        editor.insertText("@fi", replacementRange: editor.selectedRange())
        fixture.pump()
        let acceptedFolder = fixture.wait { editor.input?.onKey(.tab) == true }
        fixture.pump()
        check(acceptedFolder && editor.string == "@fixtures/", "folder completion continues the file query")
        check(editor.input?.onKey(.down) == true, "Down moves from the folder to its child")
        fixture.pump()
        let acceptedChild = fixture.wait { editor.input?.onKey(.tab) == true }
        fixture.pump()
        check(acceptedChild && editor.string == "\u{FFFC} ", "continued folder query accepts its child")

        fixture.reset(editor)
        editor.insertText("/", replacementRange: editor.selectedRange())
        fixture.pump()
        check(fixture.window.firstResponder === editor, "command trigger keeps focus")
        check(editor.input?.onKey(.tab) == true, "slash query exposes commands and consumes Tab")
        fixture.pump()
        check(fixture.session.composerMessage == "/clear ", "Tab accepts the command without submitting it")

        fixture.reset(editor)
        editor.insertText("```swift\n    let value = 1", replacementRange: editor.selectedRange())
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .return)) == true, "Return inside fenced code edits instead of sending")
        fixture.pump()
        check(fixture.session.composerMessage.hasSuffix("\n    "), "code newline keeps indentation")
        check(editor.input?.onEvent(.init(key: .tab)) == true, "Tab inside fenced code indents")
        fixture.pump()
        check(fixture.session.composerMessage.hasSuffix("\n        "), "code indentation reaches the model")

        fixture.reset(editor)
        editor.insertText("```swift\n@fi", replacementRange: editor.selectedRange())
        fixture.pump()
        check(editor.input?.onKey(.down) == false, "file-like code does not open file suggestions")
        check(editor.input?.onEvent(.init(key: .return)) == true, "Return after file-like code inserts a newline")
        fixture.pump()
        check(fixture.session.composerMessage == "```swift\n@fi\n", "code keeps literal mention text")

        fixture.reset(editor)
        editor.insertText("Describe `use @fixtures/gu` here", replacementRange: editor.selectedRange())
        editor.setSelectedRange(NSRange(location: "Describe `use @fixtures/gu".utf16.count, length: 0))
        fixture.pump()
        check(editor.input?.onKey(.down) == false, "inline code does not expose file completions")
        check(editor.input?.onKey(.tab) == false, "Tab in inline code cannot accept a file mention")
        check(editor.input?.onKey(.submit) == false, "Return in inline code cannot accept a file mention")
        check(fixture.session.composerMessage == "Describe `use @fixtures/gu` here", "inline code remains literal text")

        fixture.reset(editor)
        fixture.session.queue.append("First queued message")
        fixture.session.queue.append("Last queued message")
        fixture.pump()
        check(editor.input?.onEvent(.init(key: .upArrow)) == true, "Up in the empty field recalls a queued message")
        fixture.pump()
        check(fixture.session.composerMessage == "Last queued message", "queue recall loads the last message")
        check(
            editor.input?.onEvent(.init(key: .upArrow, modifiers: [.command, .option])) == true,
            "modified Up reorders the edited queue message")
        fixture.pump()
        check(
            fixture.session.queuedPrompts.first?.text == "Last queued message", "queue reorder uses the session model")
        check(editor.input?.onKey(.escape) == true, "Escape cancels the queued edit")
        fixture.pump()
        check(
            fixture.session.editingQueuedPrompt == nil && fixture.session.draft.isEmpty,
            "cancelling the queue edit restores an empty draft")

        if let queued = fixture.session.queuedPrompts.first {
            ComposerView(session: fixture.session).edit(queued.id)
            fixture.pump()
            check(editor.string == queued.text, "row edit opens the selected queued message")
            editor.insertText(" revised", replacementRange: editor.selectedRange())
            fixture.pump()
            editor.input?.onSubmit()
            fixture.pump()
            check(
                fixture.session.queuedPrompts.first?.text == queued.text + " revised"
                    && fixture.session.editingQueuedPrompt == nil && fixture.session.draft.isEmpty,
                "Return saves the selected queue row without sending it")
        } else {
            check(false, "cancelling a queued edit keeps the queued rows")
        }

        fixture.window.makeFirstResponder(nil)
        fixture.pump()
        check(editor.input?.isFocused?.wrappedValue == false, "resigning the editor clears composer focus")
        fixture.session.wantsComposerFocus = true
        fixture.pump()
        check(fixture.window.firstResponder === editor, "model focus request returns to the editor")

        guard let approvalSession = SessionModel.preview(in: fixture.app, agent: "claude-code"),
            let questionSession = SessionModel.preview(in: fixture.app, agent: "claude-code")
        else { throw CocoaError(.coderValueNotFound) }
        approvalSession.composerMessage = "Retain this follow-up"
        approvalSession.previewPermissionRequest(command: "swift test", reason: "Check the focused tests.")
        approvalSession.mirrorState()
        check(ComposerView(session: approvalSession).hasFieldRequest, "approval fixture mounts an ask")
        approvalSession.wantsComposerFocus = true
        ComposerView(session: approvalSession).takeFocusIfWanted()
        check(approvalSession.wantsComposerFocus, "the draft leaves approval focus requests for the instruction editor")
        check(
            approvalSession.composerMessage == "Retain this follow-up", "approval focus routing retains the follow-up")
        let request = try JSONDecoder().decode(
            CreateElicitationRequest.self,
            from: Data(
                """
                {"sessionId":"composer-field-input","mode":"form","message":"Which layout?",
                 "requestedSchema":{"type":"object","properties":{"layout":{"type":"string"}}}}
                """.utf8))
        questionSession.composerMessage = "Retain this follow-up"
        questionSession.requestQuestion(request, id: .int(1))
        check(ComposerView(session: questionSession).hasFieldRequest, "question fixture mounts an ask")
        questionSession.wantsComposerFocus = true
        ComposerView(session: questionSession).takeFocusIfWanted()
        check(questionSession.wantsComposerFocus, "the draft leaves question focus requests for the answer editor")
        check(
            questionSession.composerMessage == "Retain this follow-up", "question focus routing retains the follow-up")

        guard failures.isEmpty else {
            print("\(failures.count) composer field input regressions failed")
            exit(1)
        }
        print("Composer field input regressions passed")
    }
}

private final class ComposerFieldInputFixture {
    let window: NSWindow
    let app: AppModel
    let session: SessionModel

    init(root: URL) throws {
        let defaults = PreviewUserDefaults()
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        app = AppModel(
            plugins: PluginRegistry(previewing: [BuiltInPlugins.claudeCode]), defaults: defaults,
            catalogURL: nil, experiments: experiments)
        guard let agent = app.plugins.agent(.init(rawValue: "claude-code")) else {
            throw CocoaError(.coderValueNotFound)
        }
        session = SessionModel(
            agent: agent, id: SessionID("composer-field-input"), cwd: root,
            connection: ACPConnection(reading: .nullDevice, writing: .nullDevice, onEvent: { _ in }),
            services: app.sessions.services, supportsSteering: false, phase: .idle)
        let automation = AutomationCenter(
            goalStore: GoalStore(url: root.appending(path: "unused-goals.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        let host = NSHostingView(
            rootView: ComposerView(session: session, taskModes: modes)
                .environment(app).environment(automation).environment(CommandRegistry.shared)
                .environment(\.experimentStore, experiments))
        window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 500), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        pump()
    }

    func editor() throws -> PlatformDSTextInputMacView {
        func find(_ view: NSView) -> PlatformDSTextInputMacView? {
            if let editor = view as? PlatformDSTextInputMacView { return editor }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let content = window.contentView, let editor = find(content) else {
            throw CocoaError(.coderValueNotFound)
        }
        return editor
    }

    func focus(_ editor: NSTextView) {
        window.makeFirstResponder(nil)
        pump()
        window.makeFirstResponder(editor)
        pump()
    }

    func reset(_ editor: PlatformDSTextInputMacView) {
        editor.replaceDocument(.init())
        pump()
        focus(editor)
    }

    func pump() {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    @discardableResult
    func wait(_ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 3)
        while Date() < deadline {
            if condition() { return true }
            pump()
        }
        return false
    }
}
