import Git
import SwiftUI

/// The project owns cache choices; Scripts owns the one-time Setup command.
struct WorktreeWarmProjectSection: View {
    let project: Project

    @Environment(GitSettings.self) private var settings
    @Environment(\.undoManager) private var undoManager
    @State private var folderDraft: String?

    private var configuration: WorktreeWarmSettings { settings.warmWorktree(forProjectAt: project.url) }

    var body: some View {
        WorktreeWarmProjectContent(
            rowID: ProjectSettingsRows(project: project.id).warmWorktree,
            folders: folders,
            folderSuggestions: WorktreeWarmSettings.commonFolders.joined(separator: ", "),
            includesEnvironmentFiles: Binding(
                get: { configuration.includesEnvironmentFiles },
                set: { value in
                    var updated = configuration
                    updated.includesEnvironmentFiles = value
                    settings.setWarmWorktree(updated, forProjectAt: project.url, undoManager: undoManager)
                }),
            invalidFolders: configuration.folders.filter { !WorktreeWarmSettings.isValidFolder($0) }
        )
        .onChange(of: project.url) { folderDraft = nil }
        .onChange(of: configuration) { _, updated in
            if !updated.enabled || folderDraft.map(Self.parseFolders) != updated.folders { folderDraft = nil }
        }
    }

    private var folders: Binding<String> {
        Binding(
            get: { folderDraft ?? (configuration.enabled ? configuration.folders.joined(separator: ", ") : "") },
            set: { text in
                // Keep delimiters while typing, so a comma can start the next entry.
                folderDraft = text
                var updated = configuration
                updated.enabled = true
                updated.folders = Self.parseFolders(text)
                settings.setWarmWorktree(updated, forProjectAt: project.url, undoManager: undoManager)
            })
    }

    private static func parseFolders(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
