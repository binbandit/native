#if DEBUG
import ACP
import ApprovalAnalysis
import Experiments
import NativeAutomation
import SwiftUI

enum ApprovalPreviewFixtures {
    static let folder = "/Users/developer/Developer/native/worktrees/fix-stale-build"
    static let home = "/Users/developer"
    static let commands = [
        "git push --force origin main",
        "swift test --package-path Packages/ACP --filter PermissionRequestTests",
        "./tools/acp-schema-gen --lang swift --strict --out Packages/ACP/Sources/ACP/Generated schema/v2.json",
        "git push origin fix/stale-build",
        "rm -rf ~/Library/Developer/Xcode/DerivedData/native-bfhqjzxkdyowmrtglcaevpsnui",
    ]
    /// What the agent said before each command, as the subline shows it.
    static let reasons = [
        "Squashed into one commit, `docs: release notes for 0.9`. main's history changed, so the push needs `--force`.",
        "It fails about one run in five on CI, so I want to see it fail here before touching the fixture.",
        "I'll run the generator the repo uses, then build the package to see what changed.",
        "The fix is committed, so I'll push the branch.",
        "Every failure is a stale `.swiftmodule` in DerivedData. Clearing this project's folder there fixes it.",
    ]
    /// The force-push once its remote has been read: three commits only github.com has.
    static let forceReach = ApprovalPushReach(
        remote: "origin", branch: "main", host: "github.com", repository: "binbandit/native", ahead: 3,
        dropped: [
            .init(
                hash: "d608cec8", subject: "perf(ui): share minute updates for pull requests and usage (#42)",
                date: .now.addingTimeInterval(-7_200)),
            .init(
                hash: "3b04b19a", subject: "fix(composer): quiet follow-up prompts while agents work (#57)",
                date: .now.addingTimeInterval(-10_800)),
            .init(
                hash: "fe4ae1e1", subject: "fix(host): build and test native-host on Linux (#28)",
                date: .now.addingTimeInterval(-18_000)),
        ])
    // Several decisions can share the same ACP lifetime. Keep every one visible and distinct.
    static let distinctOptions: [PermissionOption] = [
        .init(optionId: "grant", name: "Grant for this turn", kind: .allowOnce),
        .init(optionId: "strict", name: "Grant with strict auto review", kind: .allowOnce),
        .init(optionId: "session", name: "Allow for this session", kind: .allowAlways),
        .init(optionId: "decline", name: "Decline", kind: .rejectOnce),
        .init(optionId: "cancel", name: "Cancel this turn", kind: .rejectOnce),
        .init(optionId: "block", name: "Block this host", kind: .rejectAlways),
    ]
    static let force = analyze(commands[0]).describingPushTarget(forceReach.description)
    static let routine = analyze(commands[1])
    static let unknown = analyze(commands[2])

    /// What an agent says before asking for a fixture command, matched by its program and subcommand.
    static func reason(for command: String) -> String? {
        if command.hasPrefix("git push --force") { return reasons[0] }
        if command.hasPrefix("swift test") { return reasons[1] }
        if command.hasPrefix("git push") { return reasons[3] }
        return commands.firstIndex(of: command).map { reasons[$0] }
    }

    static func analyze(_ command: String) -> ApprovalCommand {
        ApprovalCommand(command: command, workingDirectory: folder, homeDirectory: home)
    }

    static func session(in app: AppModel, command: String) -> SessionModel? {
        let session = SessionModel.preview(
            in: app, agent: "codex", cwd: folder,
            title: "Review the requested command", phase: .prompting,
            configOptions: ComposerPreviewFixtures.configOptions)
        session?.previewRunningTurn("Check the build and explain what needs approval.")
        session?.previewPermissionRequest(command: command, reason: reason(for: command))
        return session
    }

    @ViewBuilder static func card(
        command: String, failure: String? = nil, isAvailable: Bool = true, sending: Bool = false,
        options: [PermissionOption]? = nil
    ) -> some View {
        let app = AppModel.preview(.empty)
        if let session = session(in: app, command: command), let call = session.permissionRequests.first {
            let describedCall = replacingOptions(in: call, with: options)
            ApprovalSurface {
                AnnotatedApprovalView(
                    call: describedCall, agentName: "Codex", workingDirectory: folder,
                    reason: session.state.reason(forToolCall: call.id), homeDirectory: home,
                    isAvailable: isAvailable,
                    onChoose: { _ in }, onInstruct: { _ in }, sending: sending, failure: failure)
            }
            .environment(\.approvalPushReach, { _ in forceReach })
        }
    }

    private static func replacingOptions(in call: ToolCallState, with options: [PermissionOption]?) -> ToolCallState {
        var call = call
        if let options { call.permission?.options = options }
        return call
    }

    @ViewBuilder static func composer(command: String = commands[0]) -> some View {
        let app = AppModel.preview(.empty)
        let defaults = PreviewUserDefaults()
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        let _ = experiments.set(true, for: .composerNext)
        let automation = AutomationCenter(
            goalStore: GoalStore(url: URL(filePath: "/native-preview-unused/goals.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
        if let session = session(in: app, command: command) {
            ComposerView(session: session, taskModes: modes)
                .environment(app).environment(automation).environment(CommandRegistry.shared)
                .environment(\.experimentStore, experiments)
                .environment(\.approvalPushReach, { _ in forceReach })
        }
    }
}
#endif
