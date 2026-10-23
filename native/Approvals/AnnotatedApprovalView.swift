import ACP
import ApprovalAnalysis
import SwiftUI

/// The approval shared by the composer, Peek and Home. Hosts supply the request and model actions;
/// this view never answers a connection or changes an agent's command itself.
struct AnnotatedApprovalView: View {
    let call: ToolCallState
    let agentName: String
    let workingDirectory: String
    var homeDirectory: String? = nil
    var isAvailable = true
    var focusRequested = false
    var didFocus: () -> Void = {}
    let onChoose: (PermissionOption) -> Void
    let onInstruct: (String) async throws -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.permissionShortcutsEnabled) private var shortcutsEnabled
    @FocusState private var instructionFocused: Bool
    @State var instruction = ""
    @State private var sending = false
    @State private var keyboardHeld = false
    @State private var committed = false
    @State var failure: String?

    private var analysis: ApprovalCommand? {
        call.shellCommand.map {
            ApprovalCommand(
                command: $0,
                workingDirectory: call.rawInput?["cwd"]?.stringValue ?? workingDirectory,
                worktreeDirectory: workingDirectory, homeDirectory: homeDirectory)
        }
    }
    private var options: [PermissionOption] { call.permission?.options ?? [] }
    private var rejection: PermissionOption? {
        options.first { $0.kind == .rejectOnce } ?? options.first { $0.isRejection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeightCappedScrollView(maxHeight: DS.Approval.maximumHeight) {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("\(agentName) wants to \(analysis?.action ?? call.title)")
                            .font(DS.Approval.titleFont).foregroundStyle(.dsTextPrimary)
                        Text(analysis?.reason ?? "The agent asked for permission.")
                            .font(.dsBody).foregroundStyle(.dsTextTertiary)
                    }
                    if let analysis {
                        VStack(spacing: 0) {
                            ApprovalCommandDiagram(analysis: analysis)
                            if let replacement = analysis.suggestedCommand, rejection != nil {
                                Rectangle().fill(DS.Approval.separator(colorScheme)).frame(height: DS.Approval.rule)
                                fixIt(replacement)
                            }
                        }
                        .background(DS.Approval.well(colorScheme), in: .rect(cornerRadius: DS.Radius.control))
                    } else {
                        ToolCallBody(call: call, presentation: ToolPresentation(call), phase: ToolPhase(call))
                    }
                    if !isAvailable {
                        Text("Waiting for the task to reconnect before you can answer.")
                            .font(.dsBody).foregroundStyle(.dsTextSecondary)
                    }
                    footer
                    if sending {
                        Text("Sending your instruction...").font(.dsBody).foregroundStyle(.dsTextTertiary)
                    }
                    if let failure {
                        Text(failure).font(.dsBody).foregroundStyle(.dsDanger)
                    }
                }
                .padding(.horizontal, DS.Approval.inset)
                .padding(.top, DS.Space.xl)
                .padding(.bottom, DS.Approval.commandInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if rejection != nil {
                Rectangle().fill(DS.Approval.separator(colorScheme)).frame(height: DS.Approval.rule)
                HStack(alignment: .bottom, spacing: DS.Space.md) {
                    TextField("Tell \(agentName) what to do instead", text: $instruction, axis: .vertical)
                        .font(.dsCallout).foregroundStyle(.dsTextPrimary).textFieldStyle(.plain).lineLimit(1...4)
                        .accessibilityLabel("Tell \(agentName) what to do instead")
                        .focused($instructionFocused)
                        .onSubmit { sendInstruction(instruction) }
                    ComposerSendButton(
                        disabledReason: instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Enter an instruction first" : nil
                    ) { sendInstruction(instruction) }
                    .accessibilityLabel("Ask \(agentName) to do this instead")
                }
                .padding(.horizontal, DS.Approval.inset)
                .padding(.vertical, DS.Space.lg)
                .frame(minHeight: DS.Approval.instructionHeight)
            }
        }
        .onChange(of: focusRequested, initial: true) { _, requested in
            if requested { instructionFocused = true; didFocus() }
        }
        .disabled(sending || committed || !isAvailable)
        .approvalHoldKeys(
            enabled: shortcutsEnabled && isAvailable && !sending && !committed && analysis?.risk == .irreversible
        ) {
            keyboardHeld = $0
        }
    }

    private func fixIt(_ replacement: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Approval.fixItGap) {
                fixItExplanation
                Spacer(minLength: DS.Space.md)
                fixItButton(replacement)
            }
            VStack(alignment: .leading, spacing: DS.Space.md) {
                fixItExplanation
                fixItButton(replacement).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Space.md)
        .padding(.leading, DS.Approval.commandInset)
        .padding(.trailing, DS.Space.md)
    }

    private var fixItExplanation: some View {
        HStack(spacing: DS.Approval.fixItGap) {
            Text("Fix-it").font(.dsCaption).foregroundStyle(.dsTextTertiary)
            Text("\(Text("--force-with-lease").font(DS.Approval.fixItFont)) refuses if the remote tip has changed.")
                .font(.dsBody).foregroundStyle(.dsTextSecondary)
        }
    }

    private func fixItButton(_ replacement: String) -> some View {
        Button("Ask \(agentName) to Use It") {
            sendInstruction("Don't run that. Run this instead:\n\(replacement)")
        }
        .buttonStyle(ApprovalActionStyle(small: true))
        .accessibilityLabel("Ask \(agentName) to Use --force-with-lease")
        .keyboardShortcut(shortcutsEnabled ? KeyboardShortcut("y", modifiers: [.command, .shift]) : nil)
        .help("Declines this request and sends the suggested command as an instruction.")
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DS.Space.lg) {
                consequence
                Spacer(minLength: DS.Space.lg)
                actions
            }
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                consequence
                actions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private var consequence: some View {
        if let analysis, analysis.risk != .unknown {
            consequenceText(analysis.consequence).font(.dsBody).foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func consequenceText(_ value: String) -> Text {
        var text = AttributedString(value)
        if let period = value.firstIndex(of: ".") {
            let count = value.distance(from: value.startIndex, to: period) + 1
            let end = text.characters.index(text.startIndex, offsetBy: count)
            text[text.startIndex..<end].font = .dsBodyMedium
            text[text.startIndex..<end].foregroundColor = .dsTextPrimary
        }
        return Text(text)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.md) { buttons }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .trailing, spacing: DS.Space.md) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        if let rejection {
            Button {
                onChoose(rejection)
            } label: {
                actionLabel("Don't Allow", keys: "⌘⇧⌫")
            }
            .buttonStyle(ApprovalActionStyle())
            .keyboardShortcut(shortcutsEnabled ? KeyboardShortcut(.delete, modifiers: [.command, .shift]) : nil)
        }
        if analysis?.risk != .irreversible {
            ForEach(options.filter { $0.kind == .allowAlways }) { option in
                Button {
                    onChoose(option)
                } label: {
                    actionLabel(
                        options.filter { $0.kind == .allowAlways }.count == 1 ? "Always Allow" : option.name,
                        keys: options.first { $0.kind == .allowAlways }?.id == option.id ? "⌥⌘Y" : "")
                }
                .buttonStyle(ApprovalActionStyle())
                .keyboardShortcut(
                    shortcutsEnabled && options.first { $0.kind == .allowAlways }?.id == option.id
                        ? KeyboardShortcut("y", modifiers: [.command, .option]) : nil)
            }
        }
        if let allow = options.first(where: { $0.kind == .allowOnce }) {
            if analysis?.risk == .irreversible {
                ApprovalHoldButton(
                    shortcutsEnabled: shortcutsEnabled, keyboardHeld: keyboardHeld, didCommit: { committed = true }
                ) { onChoose(allow) }
            } else {
                Button {
                    onChoose(allow)
                } label: {
                    actionLabel("Allow", keys: "⌘Y")
                }
                .buttonStyle(ApprovalActionStyle(primary: true))
                .keyboardShortcut(shortcutsEnabled ? KeyboardShortcut("y", modifiers: .command) : nil)
            }
        }
    }

    private func actionLabel(_ title: String, keys: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(title)
            if shortcutsEnabled, !keys.isEmpty { Text(keys).font(.dsMonoMicro).opacity(DS.Approval.hintOpacity) }
        }
    }

    private func sendInstruction(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, !sending, !committed, !text.isEmpty else { return }
        sending = true
        failure = nil
        Task {
            do { try await onInstruct(text); instruction = "" } catch {
                failure = "Couldn't send your instruction. Your words are kept. Try again."
            }
            sending = false
        }
    }
}

#if DEBUG
#Preview("Approval - force, cache, unknown, narrow, failed, reconnecting") {
    DSPreviewPair {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                ForEach(ApprovalPreviewFixtures.commands, id: \.self) { command in
                    ApprovalPreviewFixtures.card(command: command).frame(width: 760)
                }
                ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0]).frame(width: 360)
                ApprovalPreviewFixtures.card(
                    command: ApprovalPreviewFixtures.commands[0],
                    failure: "Couldn't send your instruction. Your words are kept. Try again."
                ).frame(width: 760)
                ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0], isAvailable: false)
                    .frame(width: 760)
            }.padding(DS.Space.xl)
        }.frame(height: 900)
    }
}
#endif
