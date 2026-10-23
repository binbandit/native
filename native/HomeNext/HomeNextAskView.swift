import ACP
import SwiftUI

struct HomeNextAskView: View {
    let task: HomeNextTask
    let onReceipt: (HomeNextReceipt) -> Void
    let openTask: () -> Void

    @State private var isAnswering = false
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
            if task.status != .failed {
                Button("Open Task", action: openTask)
                    .buttonStyle(.ds(.ghost)).keyboardShortcut(.return, modifiers: .command)
                    .padding(.top, DS.Space.lg)
            }
        }
        .onChange(of: task.requestID) { answerError = nil }
    }

    @ViewBuilder private var content: some View {
        if let request = task.request, let question = request.question {
            HomeNextQuestionView(question: question) { response in
                perform(response == .decline ? "Skipped the question" : "Answered the question") {
                    try await request.session.respondToQuestion(response, for: question.id)
                }
            }
        } else if let request = task.request, let call = request.call {
            if call.kind == .switchMode {
                HomeNextPlanView(session: request.session, call: call) { option in
                    answer(option, request: request, call: call)
                }
            } else {
                ToolCallView(call: call) { option in answer(option, request: request, call: call) }
            }
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
        perform(action) { try await request.session.answerHomeNextPermission(option, call: call) }
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
            }
        }
    }
}

#if DEBUG
#Preview("Next ask - Question") { HomeNextPreviewFixtures.page(.question) }
#Preview("Next ask - Plan") { HomeNextPreviewFixtures.page(.plan) }
#Preview("Next ask - Failure") { HomeNextPreviewFixtures.page(.failure) }
#endif
