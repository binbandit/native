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
        "rm -rf ~/Library/Developer/Xcode/DerivedData/native-bfhqjzxkdyowmrtglcaevpsnui",
        "./tools/acp-schema-gen --lang swift --strict --out Packages/ACP/Sources/ACP/Generated schema/v2.json",
    ]
    static let force = analyze(commands[0])
    static let routine = analyze(commands[1])
    static let unknown = analyze(commands[2])

    static func analyze(_ command: String) -> ApprovalCommand {
        ApprovalCommand(command: command, workingDirectory: folder, homeDirectory: home)
    }

    static func session(in app: AppModel, command: String) -> SessionModel? {
        let session = SessionModel.preview(
            in: app, agent: "codex", cwd: folder,
            title: "Review the requested command", phase: .prompting,
            configOptions: ComposerPreviewFixtures.configOptions)
        session?.previewRunningTurn("Check the build and explain what needs approval.")
        session?.previewPermissionRequest(command: command)
        return session
    }

    @ViewBuilder static func card(command: String, failure: String? = nil, isAvailable: Bool = true) -> some View {
        let app = AppModel.preview(.empty)
        if let session = session(in: app, command: command), let call = session.permissionRequests.first {
            ApprovalSurface {
                AnnotatedApprovalView(
                    call: call, agentName: "Codex", workingDirectory: folder, homeDirectory: home,
                    isAvailable: isAvailable,
                    onChoose: { _ in }, onInstruct: { _ in }, failure: failure)
            }
        }
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
        }
    }
}
#endif
