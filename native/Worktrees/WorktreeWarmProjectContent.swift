import SwiftUI

/// The real project controls, independent of persistence so previews stay inert.
struct WorktreeWarmProjectContent: View {
    var rowID: SettingsRowID?
    @Binding var folders: String
    let folderSuggestions: String
    @Binding var includesEnvironmentFiles: Bool
    var invalidFolders: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading("Dependencies and caches", note: "Copy project folders into new tasks.")
            SettingsRowGroup {
                SettingsRow(
                    id: rowID, "Folders to copy",
                    description: Text("Comma-separated ignored folders or paths; leave empty to turn off.")
                ) {
                    TextField(
                        "Folders to copy", text: $folders,
                        prompt: Text(folderSuggestions).foregroundStyle(.dsTextSecondary)
                    )
                    .settingsField()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Folders to copy")
                }
                .settingsControlBelow()
                SettingsRow(
                    "Include local env files",
                    description: Text("Also copy .env and .env.local files, which may contain credentials.")
                ) {
                    SettingsSwitch("Include local env files", isOn: $includesEnvironmentFiles)
                }
            }
            if !invalidFolders.isEmpty {
                SettingsNote("Some folders will be skipped", systemImage: "exclamationmark.triangle") {
                    Text(
                        "Use relative folder names without .., .git or .env: \(invalidFolders.joined(separator: ", "))."
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview("Dependencies and caches - Empty") {
    worktreeWarmContentPreview()
}

#Preview("Dependencies and caches - Configured") {
    worktreeWarmContentPreview(folders: "node_modules, dist")
}

#Preview("Dependencies and caches - Invalid folders and env consent") {
    worktreeWarmContentPreview(
        folders: "node_modules, ../cache, .env", includesEnvironmentFiles: true, invalidFolders: ["../cache", ".env"])
}

#Preview("Dependencies and caches - Plainly") {
    worktreeWarmContentPreview().environment(\.settingsPlainly, true)
}

#Preview("Dependencies and caches - Narrow") {
    worktreeWarmContentPreview(width: 420)
}

@MainActor
private func worktreeWarmContentPreview(
    folders: String = "", includesEnvironmentFiles: Bool = false, invalidFolders: [String] = [], width: CGFloat = 720
) -> some View {
    DSPreviewPair {
        WorktreeWarmProjectContent(
            folders: .constant(folders),
            folderSuggestions: "node_modules, .venv, .build, target, Pods, DerivedData, .next, dist",
            includesEnvironmentFiles: .constant(includesEnvironmentFiles), invalidFolders: invalidFolders
        )
        .settingsPreviewPage(width: width)
    }
}
#endif
