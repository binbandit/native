import AIInstructions
import NativePolicy
import SwiftUI

/// A project's own AI instructions, for its settings page. Each purpose uses the global
/// instructions (Settings ▸ AI Instructions) or the project's own, which replace them for tasks in
/// the project and its worktrees.
///
///     AIInstructionsProjectSection(projectRoot: project.url)
struct AIInstructionsProjectSection: View {
    let projectRoot: URL

    var body: some View {
        SettingsSubheading(
            "AI instructions",
            note:
                "Added to what Native writes with AI for this project. Each uses your global instructions unless you give it the project's own."
        )
        SettingsRowGroup {
            ForEach(AIInstructionPurpose.allCases) { purpose in
                AIInstructionProjectRow(purpose: purpose, projectRoot: projectRoot)
            }
        }
        .settingsManaged(by: .aiInstructions)
    }
}

/// One purpose for a project: "Use global" or "Custom", and the project's own instructions while
/// it has them.
private struct AIInstructionProjectRow: View {
    enum Mode: Hashable {
        case global, custom
    }

    let purpose: AIInstructionPurpose
    let projectRoot: URL

    @Environment(GitSettings.self) private var gitSettings
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    @Environment(\.settingsLockReason) private var lockReason
    /// The project's own text from before "Use global", which Custom brings back.
    @State private var stashed: String?
    private let store = AIInstructionsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(purpose.title, description: Text(description)) {
                SettingsSelect(
                    label: purpose.title, selection: mode,
                    options: [.init(value: .global, title: "Use global"), .init(value: .custom, title: "Custom")])
            }
            if lockReason == nil, store.projectText(for: purpose, in: projectRoot) != nil {
                AIInstructionEditor(
                    purpose: purpose, text: text,
                    branchPrefix: gitSettings.branchPrefix(
                        forProjectAt: projectRoot, gitHubLogin: gitHub?.currentLogin),
                    project: projectRoot)
            }
        }
    }

    /// What applies now: the project's own, the global text, or none.
    private var description: String {
        if store.projectText(for: purpose, in: projectRoot) != nil {
            return "This project's own, in place of your global instructions."
        }
        let global = store.text(for: purpose).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !global.isEmpty else { return "No global instructions. \(purpose.summary)" }
        let firstLine = global.split(whereSeparator: \.isNewline).first.map(String.init) ?? global
        return "Global: \u{201C}\(firstLine)\u{201D}"
    }

    private var mode: Binding<Mode> {
        Binding(
            get: { store.projectText(for: purpose, in: projectRoot) == nil ? .global : .custom },
            set: { mode in
                switch mode {
                case .global:
                    stashed = store.projectText(for: purpose, in: projectRoot)
                    store.setProjectText(nil, for: purpose, in: projectRoot)
                case .custom:
                    // What the project had before, or the global text to start from as a tweak of it.
                    store.setProjectText(stashed ?? store.text(for: purpose), for: purpose, in: projectRoot)
                }
            }
        )
    }

    private var text: Binding<String> {
        Binding(
            get: { store.projectText(for: purpose, in: projectRoot) ?? "" },
            set: { store.setProjectText($0, for: purpose, in: projectRoot) }
        )
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Project instructions") {
    DSPreviewPair {
        AIInstructionsProjectSection(
            projectRoot: URL(filePath: AppPreviewFixtures.nativeFolder, directoryHint: .isDirectory)
        )
        .settingsPreviewPage()
    }
    .environment(GitSettings(defaults: PreviewUserDefaults()))
    .environment(GitHubModel.preview())
}
#endif
