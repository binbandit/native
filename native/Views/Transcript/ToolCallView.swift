import ACP
import SwiftUI

/// One tool call as a dense one-line row: its category's glyph, verb and subject, then how it
/// stands (a running clock, how long it took, why it failed). Every row starts closed, running or
/// done; a click, Space on the focused row, or the accessibility press opens its output in a framed
/// panel below. A failed call adds its first line of error output under the row while closed. While
/// the agent waits for approval the details stay open above the permission buttons.
struct ToolCallView: View, Equatable {
    let call: ToolCallState
    var permissionPresentation: ToolPermissionButtons.Presentation = .standard
    let onChoose: (PermissionOption) -> Void

    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?
    /// For rows shown outside a transcript, which has no `TranscriptDisclosures`.
    @State private var isOpenHere = false
    @Experiment(.composerNext) private var finePrint
    @Environment(\.isPrimaryTranscript) private var isPrimaryTranscript

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
        let presentation = ToolPresentation(call)
        let phase = ToolPhase(call)
        let hasDetails = detailsAvailable(for: presentation)
        let inComposer = finePrint && isPrimaryTranscript && call.permission != nil
        let showsDetails = !inComposer && hasDetails && (isOpen || phase == .awaitingApproval)
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ToolRow(
                presentation: presentation,
                phase: phase,
                timing: ToolRowTiming(call),
                isExpandable: hasDetails && phase != .awaitingApproval,
                isExpanded: showsDetails,
                toggle: toggle,
                accessory: {
                    if showsDetails, case .command(let command) = presentation.body {
                        CopyButton(text: ToolOutput.copyText(command: command, call: call))
                    }
                }
            )
            if !showsDetails, phase == .failed, let hint = ToolOutput.failureHint(of: call) {
                ToolFailureHint(text: hint)
            }
            if showsDetails {
                ToolDetailFrame(isEmphasized: phase == .awaitingApproval) {
                    ToolCallBody(call: call, presentation: presentation, phase: phase)
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
        .animation(.smooth, value: phase)
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

/// A failed call's first line of error output, under its closed row, so the reason shows without
/// opening it.
private struct ToolFailureHint: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .padding(.leading, DS.Size.rowLeading + DS.Space.sm)
            .padding(.bottom, DS.Space.xs)
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

private struct CopyButton: View {
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
        }
        .buttonStyle(.plain)
        .help("Copy command and output")
        .accessibilityLabel("Copy command and output")
    }
}

#if DEBUG
#Preview("Tool calls") {
    ScrollView {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(TranscriptFixtures.toolCalls, id: \.id) { call in
                ToolCallView(call: call) { _ in }
            }
        }
        .padding(20)
    }
    .frame(width: 640, height: 760)
}
#endif
