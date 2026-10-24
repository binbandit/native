import ACP
import SwiftUI

/// A subagent's own conversation, beside its parent's. Subagents can't be prompted; the well can
/// reveal their existing question form without adding an unrestricted composer.
struct SubagentInspector: View {
    let subagent: SubagentState
    /// The child session, once the agent has sent any of its traffic.
    let child: SessionModel?
    var showsQuestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let child {
                TranscriptView(session: child) { _ in }
            } else {
                ContentUnavailableView(
                    "Waiting for the subagent", systemImage: "person.2",
                    description: Text("Its conversation appears here as it works.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(.dsBackground)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if showsQuestions, let session = child?.pendingQuestionSession, let question = session.pendingQuestion {
                ComposerSurface {
                    AgentQuestionDock(session: session, question: question)
                        .id(question.id)
                }
                .padding(DS.Space.md)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(subagent.title ?? "Subagent")
                    .font(.headline)
                if let description = subagent.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                SubagentStatusLabel(state: subagent.workState)
            }
            Spacer(minLength: 8)
            if subagent.canCancel, subagent.workState?.isWorking == true, let child {
                Button("Stop", systemImage: "stop.fill") {
                    Task { await child.cancel() }
                }
                .dsGlassButtonStyle()
                .help("Stop this subagent without stopping the main task")
            }
        }
        .padding(16)
    }
}

#if DEBUG
#Preview("Subagent inspector - Well question") {
    let app = AppModel.preview()
    let subagent = SubagentPreviewFixtures.subagents[1]
    let child = SessionModel.preview(in: app, id: subagent.id.rawValue, title: subagent.title)
    let json = #"""
        {"sessionId":"preview-child","mode":"form","message":"Which layout should the helper check?",
         "requestedSchema":{"type":"object","properties":{"layout":{"type":"string","title":"Layout",
         "description":"Which layout should the helper check?","oneOf":[
         {"const":"narrow","title":"Narrow"},{"const":"wide","title":"Wide"}]}}}}
        """#
    if let request = SessionModel.previewDecode(CreateElicitationRequest.self, json) {
        child?.requestQuestion(request, id: .string("well-question"))
    }
    return DSPreviewPair {
        SubagentInspector(subagent: subagent, child: child, showsQuestions: true)
            .frame(width: DS.SessionTools.sidePanelIdealWidth, height: DS.TaskWell.panelWidth)
    }
}

#Preview("Subagent inspector") {
    let app = AppModel.preview()
    let subagents = SubagentPreviewFixtures.subagents
    let child = SessionModel.preview(in: app, id: subagents[0].id.rawValue, title: subagents[0].title)
    child?.previewExchange(
        "Find where the composer queues follow-ups and how Send Now reorders them",
        reply:
            "Follow-ups queue in `SessionModel+Turns.swift` (`enqueue`). Send Now steers when the agent can, otherwise it stops the turn and sends next."
    )
    return DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            SubagentInspector(subagent: subagents[0], child: child)
                .frame(width: 380, height: 420)
            // Before the agent has sent any of the subagent's traffic.
            SubagentInspector(subagent: subagents[1], child: nil)
                .frame(width: 380, height: 420)
        }
    }
}
#endif
