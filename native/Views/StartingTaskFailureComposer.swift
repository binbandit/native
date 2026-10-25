import NativeSetup
import SwiftUI

/// A starting task's failure in the composer's place (Fine print): the failure, and under it the
/// task's message, still editable, which goes out once the task starts.
struct StartingTaskFailureComposer: View {
    @Bindable var task: StartingTask
    let failure: StartingTask.Failure

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var source: [AgentStartDiagnostic.SourceLine] = []
    @State private var fixIt: AgentStartFixIt?
    @State private var fixFailure: String?
    @State private var isFixing = false
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        let diagnostic = failure.diagnostic
        ApprovalSurface {
            VStack(spacing: 0) {
                AgentStartFailureView(
                    agentName: task.agent.displayName,
                    title: diagnostic == nil ? failure.title : "\(task.agent.displayName) couldn't start",
                    output: failure.needsSignIn || failure.canUseProjectFolder ? "" : failure.message,
                    explanation: failure.needsSignIn || failure.canUseProjectFolder ? failure.message : nil,
                    diagnostic: diagnostic,
                    displayPath: diagnostic.map {
                        task.device == .thisMac ? URL(filePath: $0.path).abbreviatedPath : $0.path
                    },
                    source: source,
                    fixIt: fixFailure == nil ? fixIt : nil,
                    recovery: recovery,
                    draft: task.isSendRequested ? .waiting : task.draft.isEmpty ? .none : .kept,
                    fixFailure: fixFailure,
                    isWorking: isFixing,
                    onRecover: recover,
                    onRetry: { Task { await model.retry(task) } },
                    onFix: fix
                )
                Rectangle().fill(DS.Approval.separator(colorScheme)).frame(height: DS.Approval.rule)
                editor
            }
        }
        .task(id: failure) {
            fixFailure = nil
            source = await model.startFailureSource(of: task)
            fixIt = await model.startFixIt(for: task)
        }
    }

    private var recovery: AgentStartFailureView.Recovery {
        if failure.needsSignIn { return .signIn }
        if failure.canUseProjectFolder { return .projectFolder }
        return .retry(restarts: failure.needsRestart)
    }

    private var editor: some View {
        HStack(alignment: .bottom, spacing: DS.Space.md) {
            ComposerEditor(
                text: $task.draft, selection: $selection,
                placeholder: "What would you like \(task.agent.displayName) to work on?", isFocused: $isFocused,
                insets: DS.Approval.editorInsets, maximumHeight: DS.Approval.instructionMaximumHeight
            ) { press in
                guard press.key == .return, press.modifiers.isDisjoint(with: [.shift, .option]),
                    !PlatformTextInput.isComposing
                else { return .ignored }
                send()
                return .handled
            }
            if task.isSendRequested {
                Button("Don't Send") { task.isSendRequested = false }
                    .buttonStyle(ApprovalActionStyle(quiet: true))
                    .help("Keep the message here when the task starts")
            } else {
                ComposerSendButton(
                    disabledReason: task.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Write a message first" : nil,
                    action: send)
            }
        }
        .padding(.horizontal, DS.Approval.inset)
        .padding(.vertical, DS.Space.lg)
        .frame(minHeight: DS.Approval.instructionHeight)
    }

    private func send() {
        guard !task.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        task.isSendRequested = true
    }

    private func recover() {
        switch recovery {
        case .signIn: model.signInPrompt = task.agent.id
        case .projectFolder: Task { await model.startInProjectFolder(task) }
        case .retry: Task { await model.retry(task) }
        }
    }

    private func fix() {
        isFixing = true
        Task {
            do throws(AgentStartFile.Failure) {
                try await model.applyStartFixIt(to: task)
            } catch {
                fixFailure = error.localizedDescription
            }
            isFixing = false
        }
    }
}
