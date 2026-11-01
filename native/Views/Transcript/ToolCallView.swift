import ACP
import SwiftUI

/// One tool call as one line (`ToolLine`): its glyph and plain sentence, then how it stands (a
/// running clock, a long call's time, why it didn't succeed). Every row starts closed, running or
/// done; a click, Space on the focused row, or the accessibility press opens its output in a framed
/// panel below. While the agent waits for approval the details stay open above the permission
/// buttons.
struct ToolCallView: View, Equatable {
    let call: ToolCallState
    var permissionPresentation: ToolPermissionButtons.Presentation = .standard
    let onChoose: (PermissionOption) -> Void

    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?
    /// For rows shown outside a transcript, which has no `TranscriptDisclosures`.
    @State private var isOpenHere = false
    @Experiment(.composerNext) private var finePrint
    @Environment(\.isPrimaryTranscript) private var isPrimaryTranscript
    @Environment(\.toolWorkspaceRoot) private var root

    /// Rows only change with their call; `onChoose` always answers the same session.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.call == rhs.call && lhs.permissionPresentation == rhs.permissionPresentation
    }

    var body: some View {
        if let questions = AskedQuestions(call), !questions.entries.isEmpty {
            AskedQuestionsView(questions: questions)
        } else if call.permission == nil, NativeScriptCallLine.isScriptCall(call) {
            NativeScriptCallLine(call: call)
        } else {
            row
        }
    }

    private var isOpen: Bool {
        disclosures?.isOpen(call.id) ?? isOpenHere
    }

    private func toggle() {
        withAnimation(.reveal) {
            if let disclosures {
                disclosures.toggle(call.id)
            } else {
                isOpenHere.toggle()
            }
        }
    }

    @ViewBuilder private var row: some View {
        let presentation = ToolPresentation(call, root: root)
        let phase = presentation.phase
        let hasDetails = detailsAvailable(for: presentation)
        let inComposer = finePrint && isPrimaryTranscript && call.permission != nil
        let showsDetails = !inComposer && hasDetails && (isOpen || phase == .awaitingApproval)
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ToolLine(
                glyph: presentation.glyph,
                sentence: presentation.sentence,
                stats: presentation.stats,
                isBusy: phase == .running,
                isExpandable: hasDetails && phase != .awaitingApproval,
                isExpanded: showsDetails,
                help: presentation.wording.detail,
                accessibilityStatus: accessibilityStatus(presentation),
                toggle: toggle
            ) {
                if showsDetails, case .command(let command) = presentation.body {
                    ToolCopyButton(text: ToolOutput.copyText(command: command, call: call))
                }
                ToolLineStatus(
                    phase: phase, outcome: presentation.outcome, startedAt: call.startedAt,
                    finishedAt: call.finishedAt)
            }
            // Under the sentence, so the panel and the buttons read as the row's own.
            VStack(alignment: .leading, spacing: 0) {
                if showsDetails {
                    ToolDetailFrame(isEmphasized: phase == .awaitingApproval) {
                        ToolCallBody(call: call, presentation: presentation)
                    }
                    .transition(RevealTransition())
                }
                if let permission = call.permission, !inComposer {
                    ToolPermissionButtons(
                        options: permission.options, onChoose: onChoose, presentation: permissionPresentation
                    )
                    .padding(.top, DS.Space.sm)
                    .transition(.opacity)
                }
            }
            .padding(.leading, DS.Size.rowLeading + DS.Space.sm)
        }
        .animation(.smooth, value: phase)
    }

    private func accessibilityStatus(_ presentation: ToolPresentation) -> String {
        presentation.outcome ?? (presentation.phase == .running ? "Running" : "Completed")
    }

    private func detailsAvailable(for presentation: ToolPresentation) -> Bool {
        switch presentation.body {
        case .command, .mcp: return true
        case .generic, .diff, .lines: break
        }
        guard call.content.isEmpty, ToolOutput.printed(by: call) == nil else { return true }
        guard let rawInput = call.rawInput else { return false }
        return rawInput != .null && !rawInput.isEmptyObject
    }
}

/// The framed panel a row's details open into, capped in height and scrolling beyond that.
private struct ToolDetailFrame<Content: View>: View {
    let isEmphasized: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HeightCappedScrollView(maxHeight: TranscriptMetrics.toolDetailMaxHeight) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.dsSurfaceSunken, in: shape)
        .overlay {
            shape.strokeBorder(isEmphasized ? Color.dsAccent.opacity(0.5) : .dsSeparator)
        }
        .clipShape(shape)
        .containerShape(shape)
    }
}

/// Copies a command and what it printed, at the trailing edge of its open row.
private struct ToolCopyButton: View {
    let text: String

    @State private var didCopy = false

    var body: some View {
        Button {
            DSPasteboard.copy(text)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .font(.dsMicro)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                .contentShape(.rect)
                .dsHitTarget(DS.Size.rowLeading)
        }
        .buttonStyle(.plain)
        .help("Copy command and output")
        .accessibilityLabel("Copy command and output")
    }
}

#if DEBUG
#Preview("Tool calls - Every kind and state") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(TranscriptFixtures.toolCalls, id: \.id) { call in
                ToolCallView(call: call) { _ in }
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 620)
    }
}

#Preview("Tool calls - Opened, failed and huge output") {
    let disclosures = TranscriptDisclosures()
    let calls = TranscriptFixtures.openedToolCalls
    for call in calls { disclosures.toggle(call.id) }
    return DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(calls, id: \.id) { call in
                ToolCallView(call: call) { _ in }
            }
        }
        .environment(disclosures)
        .padding(DS.Space.xl)
        .frame(width: 620)
    }
}

#Preview("Tool calls - Narrow") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(TranscriptFixtures.toolCalls.prefix(8), id: \.id) { call in
                ToolCallView(call: call) { _ in }
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 320)
    }
}
#endif
