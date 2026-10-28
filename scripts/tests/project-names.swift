import Foundation
import SwiftUI

@testable import Native

@main @MainActor private struct ProjectNameChecks {
    static func main() throws {
        let app = AppModel.preview(.empty)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "native-project-names-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let work = scratch.appending(path: "work/native")
        let personal = scratch.appending(path: "personal/native")
        for url in [work, personal] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let defaults = PreviewUserDefaults()
        let persisted = Projects(defaults: defaults)
        let saved = persisted.add(work)
        persisted.rename(saved.id, to: "Saved Native")
        require(
            Projects(defaults: defaults).project(saved.id)?.name == "Saved Native",
            "project records reload their custom name")
        persisted.remove(saved.id)
        require(Projects(defaults: defaults).add(work).name == "Saved Native", "a removed name survives a fresh store")
        let first = app.projects.add(work)
        let second = app.projects.add(personal)
        require(app.projects.project(first.id)?.name == "native · work", "first duplicate has its parent")
        require(app.projects.project(second.id)?.name == "native · personal", "second duplicate has its parent")
        app.projects.archive(second.id)
        require(
            app.projects.project(first.id)?.name == "native · work",
            "an archived duplicate keeps the open label distinct")
        require(app.projects.archived.first?.name == "native · personal", "archive labels use the same disambiguation")
        app.projects.unarchive(second.id)
        let encoded = try JSONEncoder().encode(app.projects.all)
        let decoded = try JSONDecoder().decode([Project].self, from: encoded)
        require(
            decoded.allSatisfy { $0.nameQualifier == nil && $0.displayName == nil },
            "automatic suffixes never persist as custom names")
        app.requestRenameProject(first.id)
        require(app.projectNameDraft == "native", "the rename editor excludes the automatic suffix")
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        app.renameProject(first.id, to: "  Native at Work  ", undoManager: undo)
        undo.endUndoGrouping()
        require(app.projects.project(first.id)?.name == "Native at Work", "rename goes through the model")
        require(app.projects.project(second.id)?.name == "native", "the other duplicate loses its suffix")
        require(FileManager.default.fileExists(atPath: work.path), "rename leaves the folder alone")
        undo.undo()
        require(app.projects.project(first.id)?.name == "native · work", "undo restores the resolved name")
        undo.redo()
        require(app.projects.project(first.id)?.name == "Native at Work", "redo restores the custom name")
        app.projects.remove(first.id)
        let reopened = app.projects.add(work)
        require(reopened.name == "Native at Work", "removing and reopening retains the name")
        app.projects.remove(reopened.id)
        let moved = scratch.appending(path: "moved-native")
        try FileManager.default.moveItem(at: work, to: moved)
        let relocated = app.projects.add(moved)
        require(relocated.name == "Native at Work", "the same folder keeps its name after moving")
        app.renameProject(relocated.id, to: "\n ")
        require(app.projects.project(relocated.id)?.name == "moved-native", "clearing restores the folder name")
        require(app.projects.project(relocated.id)?.displayName == nil, "the automatic name is never saved as custom")
        app.projects.archive(relocated.id)
        app.renameProject(relocated.id, to: "Archived Native")
        app.projects.unarchive(relocated.id)
        require(app.projects.project(relocated.id)?.name == "Archived Native", "archived renames survive unarchive")
        print("PASS: model rename, undo/redo, duplicates, clearing, reopen, move and archive")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
