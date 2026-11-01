import ACP
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@testable import Native

@main
@MainActor
private struct ComposerDropChecks {
    static func main() async throws {
        let fixture = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        guard !ComposerAttachmentDrop.accepts(NSItemProvider(object: "a text selection" as NSString)) else {
            throw Failure("An ordinary text selection was admitted as a file attachment")
        }
        guard !ComposerDropItem.acceptsPaste(NSItemProvider(object: "a text selection" as NSString)) else {
            throw Failure("Ordinary text paste was admitted as a file attachment")
        }
        for original in ["Before selected after", "`code` before selected after"] {
            let draft = Draft(original)
            let undo = UndoManager()
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            ComposerEditorUndo.record(
                Binding(get: { draft.text }, set: { draft.text = $0 }), using: undo, actionName: "Drop Text")
            draft.text = original.replacingOccurrences(of: "selected", with: "dropped")
            undo.endUndoGrouping()
            let replaced = draft.text
            undo.undo()
            guard draft.text == original else { throw Failure("Text drop undo lost the replaced selection") }
            undo.redo()
            guard draft.text == replaced, undo.undoActionName == "Drop Text" else {
                throw Failure("Text drop redo lost the edit or its action name")
            }
        }
        for name in ["brief.txt", "pixel.png", "folder"] {
            let url = fixture.appending(path: name)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) {
                done in
                done(url.dataRepresentation, nil)
                return nil
            }
            provider.registerObject(url.path as NSString, visibility: .all)
            guard ComposerAttachmentDrop.accepts(provider) else { throw Failure("A file/text payload was refused") }
            let result = try await load(provider)
            guard case .file(let imported) = result, imported == url else {
                throw Failure("A mixed file/text payload did not import as its file URL: \(name)")
            }
            let attachment = try PromptAttachment.load(imported)
            if name == "pixel.png" {
                guard case .image = attachment.content else { throw Failure("Image file lost its image contents") }
                guard attachment.delivery(to: PromptCapabilities()) == .link else {
                    throw Failure("An agent without image support did not receive a file reference")
                }
            } else if name == "folder", attachment.content != .reference {
                throw Failure("A folder did not become a file reference")
            }
            let once = try PromptAttachment.adding(attachment, to: [])
            guard try PromptAttachment.adding(attachment, to: once).count == 1 else {
                throw Failure("Dropping the same file twice duplicated it")
            }
        }
        let image = try Data(contentsOf: fixture.appending(path: "pixel.png"))
        let fileProvider = NSItemProvider()
        let source = fixture.appending(path: "brief.txt")
        fileProvider.registerFileRepresentation(
            forTypeIdentifier: UTType.data.identifier, fileOptions: .openInPlace, visibility: .all
        ) { done in
            done(source, true, nil)
            return nil
        }
        guard ComposerAttachmentDrop.accepts(fileProvider) else { throw Failure("A file representation was refused") }
        guard case .file(let retained) = try await load(fileProvider), retained != source,
            try Data(contentsOf: retained) == Data(contentsOf: source)
        else { throw Failure("A provider's temporary file was not retained") }
        try FileManager.default.removeItem(at: retained.deletingLastPathComponent())
        let document = NSItemProvider()
        document.registerFileRepresentation(
            forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all
        ) { done in
            done(source, false, nil)
            return nil
        }
        guard ComposerDropItem.acceptsPaste(document),
            !document.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        else { throw Failure("A typed document without a file URL was excluded from paste") }
        guard case .file(let retainedDocument) = try await ComposerDropItem.load(document), retainedDocument != source,
            try Data(contentsOf: retainedDocument) == Data(contentsOf: source)
        else { throw Failure("A pasted typed document was not retained") }
        try FileManager.default.removeItem(at: retainedDocument.deletingLastPathComponent())
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { done in
            done(image, nil)
            return nil
        }
        guard case .image(let imported, .png) = try await load(provider), imported == image else {
            throw Failure("A raw picture did not import as an image")
        }
        print(
            "PASS: file/text imports, images and folders, image fallback, duplicates, raw pictures, typed document paste, text drop undo/redo"
        )
    }

    private static func load(_ provider: NSItemProvider) async throws -> ComposerDropItem {
        try await ComposerDropItem.load(provider)
    }

    private final class Draft {
        var text: String
        init(_ text: String) { self.text = text }
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
