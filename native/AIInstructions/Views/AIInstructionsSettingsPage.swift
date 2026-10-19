import AIInstructions
import NativePolicy
import SwiftUI

extension SettingsPane.ID {
    static let aiInstructions = Self("ai-instructions")
}

extension SettingsPane {
    static let aiInstructions = SettingsPane(
        id: .aiInstructions,
        title: "AI Instructions",
        systemImage: "text.bubble",
        group: .agents,
        order: 27,
        keywords: ["prompt", "system prompt", "instructions", "apple intelligence", "generate", "jira"],
        searchEntries: {
            AIInstructionPurpose.allCases.map {
                SettingsSearchEntry(
                    id: $0.settingsRowID, title: $0.title, description: $0.summary, keywords: $0.keywords)
            }
        },
        content: { AIInstructionsSettingsPage() }
    )
}

/// Settings ▸ AI Instructions: the user's own instructions for each thing Native writes with AI,
/// added to Native's built-in ones. On-device purposes come first, then what's sent to agents.
struct AIInstructionsSettingsPage: View {
    @Environment(GitSettings.self) private var gitSettings
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    private let store = AIInstructionsStore.shared

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "AI Instructions",
                description: Text(
                    "Your own instructions for what Native writes with AI. They're added to Native's built-in instructions, which keep each result in the shape Native needs. A project can replace them in its settings."
                ))
            SettingsSubheading("Written on this Mac", note: "Apple Intelligence writes these privately, on this Mac.")
            if let reason = PullRequestDrafter.unavailableReason {
                // Nothing here is written until it's available, so say so before anyone tunes it.
                NoticeBanner(
                    tone: .warning, title: "Apple Intelligence isn't available", detail: reason,
                    footnote: "Your instructions are kept and apply once it is.")
            }
            rows(for: AIInstructionPurpose.allCases.filter { $0.generator == .onDevice })
            SettingsSubheading("Sent to your agent", note: "Added to the message Native sends the task's agent.")
            rows(for: AIInstructionPurpose.allCases.filter { $0.generator == .agent })
        }
        .settingsManaged(by: .aiInstructions)
    }

    private func rows(for purposes: [AIInstructionPurpose]) -> some View {
        SettingsRowGroup {
            ForEach(purposes) { purpose in
                SettingsRow(
                    id: purpose.settingsRowID, purpose.title, description: Text(purpose.summary),
                    detail: detail(for: purpose)
                ) {
                    AIInstructionEditor(
                        purpose: purpose, text: text(for: purpose),
                        branchPrefix: gitSettings.branchPrefix(gitHubLogin: gitHub?.currentLogin))
                }
            }
        }
        .settingsControlBelow()
    }

    private func text(for purpose: AIInstructionPurpose) -> Binding<String> {
        Binding(get: { store.text(for: purpose) }, set: { store.setText($0, for: purpose) })
    }

    /// Projects with their own instructions for the purpose, which these don't reach.
    private func detail(for purpose: AIInstructionPurpose) -> Text? {
        guard store.managed == nil else { return nil }
        let names = store.projectNames(overriding: purpose)
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and))
        return Text("\(list) \(names.count == 1 ? "uses its" : "use their") own instructions instead.")
    }
}
