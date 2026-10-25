import ACP
import SwiftUI

struct HomeNextAskView: View {
    let task: HomeNextTask
    let onReceipt: (HomeNextReceipt) -> Void
    let openTask: () -> Void

    @Environment(AppModel.self) private var model
    @State private var wantsInstructionFocus = false
    @State private var isAnswering = false
    @State private var approvalAttempt = 0
    @State private var answerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                TaskSignal(status: task.status, placement: .well, attentionSince: task.date)
                Text(
                    "\(task.request?.session.agentName ?? task.agent) \(task.status == .failed ? "stopped" : "is waiting on you")"
                )
                if let date = task.date {
                    Text("·")
                    DSMinuteTimeline { now in Text(DSFormat.compactAge(date, now: now)) }
                }
                Spacer(minLength: DS.Space.md)
                if let host = task.host { Label(host, systemImage: "desktopcomputer").foregroundStyle(.dsTextTertiary) }
            }
            .font(.dsBody).foregroundStyle(.dsTextSecondary)
            Text(task.title).font(DS.HomeNext.titleFont).tracking(DS.HomeNext.titleTracking)
                .foregroundStyle(.dsTextPrimary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.HomeNext.titleTop).padding(.bottom, DS.HomeNext.askBottom)
                .accessibilityAddTraits(.isHeader)
            content
                .id(task.requestID)
                .disabled(isAnswering)
            if let answerError {
                ErrorState("Couldn't complete that action", recovery: "Your task is still here.", details: answerError)
                    .padding(.top, DS.Space.lg)
            }
            if task.status != .failed, task.request?.call == nil {
                Button("Open Task", action: openTask)
                    .buttonStyle(.ds(.ghost)).keyboardShortcut(.return, modifiers: .command)
                    .padding(.top, DS.Space.lg)
            }
        }
        .onChange(of: task.requestID) { answerError = nil }
        .focusedSceneValue(\.taskPeekInstructionFocus, task.request?.call == nil ? nil : $wantsInstructionFocus)
        .environment(\.legacyAskShortcutEnabled, model.legacyAskShortcutEnabled(in: .shared))
        .environment(\.permissionShortcutsEnabled, model.taskPeek.request == nil)
    }

    @ViewBuilder private var content: some View {
        if let request = task.request, let question = request.question {
            HomeNextQuestionView(question: question) { response in
                perform(response == .decline ? "Skipped the question" : "Answered the question") {
                    try await request.session.respondToQuestion(response, for: question.id)
                }
            }
        } else if let request = task.request, let call = request.call {
            AnnotatedApprovalView(
                call: call, agentName: request.session.agentName, workingDirectory: request.session.cwd.path,
                homeDirectory: model.device(of: task.id) == .thisMac ? NSHomeDirectory() : nil,
                knowledge: model.plugins.commandKnowledge,
                isAvailable: request.session.phase != .disconnected && model.taskIsReachable(task.id),
                responseAttempt: approvalAttempt,
                focusRequested: wantsInstructionFocus, didFocus: { wantsInstructionFocus = false },
                planEntries: call.kind == .switchMode ? request.session.state.currentTurnPlan : [],
                showMorePlan: { model.peekHomeNextTask(task) }, openTask: openTask,
                onChoose: { answer($0, request: request, call: call) },
                onInstruct: { text in
                    try await request.session.instructBeforeDecliningPermission(text, call: call)
                    onReceipt(
                        HomeNextReceipt(task: task.id, title: task.title, action: "Sent your instruction", date: .now))
                }
            )
            // A hold belongs to this exact command. Failed delivery must permit another attempt.
            .id(call)
            .padding(.horizontal, -DS.Approval.inset)
            .padding(.top, -DS.Space.xl)
            .clipped()
        } else if task.status == .failed, let session = task.session {
            let turnID = session.state.turns.last?.id
            HomeNextFailureView(session: session, openTask: openTask) {
                perform("Asked to retry") { try await session.retryHomeNext(turnID: turnID) }
            }
        } else {
            Text(task.ask).font(DS.HomeNext.ledeFont).foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answer(_ option: PermissionOption, request: HomeNextRequest, call: ToolCallState) {
        let action =
            call.kind == .switchMode
            ? (option.isRejection ? "Requested a revised plan" : "Approved the plan")
            : "\(option.isRejection ? "Rejected" : "Allowed") \(call.shellCommand ?? call.title)"
        perform(action) { try await request.session.respondToPermission(option, call: call) }
    }

    private func perform(_ action: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !isAnswering else { return }
        isAnswering = true
        answerError = nil
        Task {
            defer { isAnswering = false }
            do {
                try await operation()
                onReceipt(HomeNextReceipt(task: task.id, title: task.title, action: action, date: .now))
            } catch {
                answerError = error.localizedDescription
                if task.request?.call != nil { approvalAttempt += 1 }
            }
        }
    }
}

#if DEBUG
#Preview("Next ask - Question") { HomeNextPreviewFixtures.page(.question) }
#Preview("Next ask - Plan") { HomeNextPreviewFixtures.page(.plan) }
#Preview("Next ask - Narrow plan") { HomeNextPreviewFixtures.page(.plan, narrow: true) }
#Preview("Next ask - Failure") { HomeNextPreviewFixtures.page(.failure) }
#Preview("Next ask - Plan without steps") { HomeNextPreviewFixtures.page(.planText) }
#Preview("Next ask - Previous plan") { HomeNextPreviewFixtures.page(.planRetained) }
#Preview("Next ask - Destructive hold") { HomeNextPreviewFixtures.page(.destructive) }
#Preview("Next ask - Unknown command") { HomeNextPreviewFixtures.page(.unknown) }
#Preview("Next ask - Plan delivery failure") { HomeNextPreviewFixtures.page(.planFailure) }
#Preview("Next ask - Delivery failure") { HomeNextPreviewFixtures.page(.approvalFailure) }
#endif
