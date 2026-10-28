import ACP
import ApprovalAnalysis
import NativePolicy
import SwiftUI

/// The approval shared by the composer, Peek and Home. Hosts supply the request and model actions;
/// this view never answers a connection or changes an agent's command itself.
struct AnnotatedApprovalView: View {
    let call: ToolCallState
    let agentName: String
    let workingDirectory: String
    var homeDirectory: String? = nil
    var knowledge: CommandKnowledge = .bundled
    var isAvailable = true
    var responseAttempt = 0
    var forceReducedMotion = false
    var focusRequested = false
    var didFocus: () -> Void = {}
    var planEntries: [PlanEntry] = []
    var showMorePlan: (() -> Void)?
    var openTask: (() -> Void)?
    @State var planExpanded = false
    let onChoose: (PermissionOption) -> Void
    let onInstruct: (String) async throws -> Void

    @Environment(PolicyCenter.self) private var policy: PolicyCenter?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.legacyAskShortcutEnabled) private var legacyShortcut
    @Environment(\.permissionShortcutsEnabled) private var shortcutsEnabled
    @FocusState private var instructionFocused: Bool
    @State var instruction = ""
    @State var sending = false
    @State private var instructionSelection: TextSelection?
    @State private var keyboardHeld = false
    @State private var committed = false
    @State var failure: String?

    private var analysis: ApprovalCommand? {
        call.shellCommand.map {
            ApprovalCommand(
                command: $0,
                workingDirectory: call.rawInput?["cwd"]?.stringValue ?? workingDirectory,
                worktreeDirectory: workingDirectory, homeDirectory: homeDirectory, knowledge: knowledge)
        }
    }
    private var options: [PermissionOption] { call.permission?.options ?? [] }
    private var rejection: PermissionOption? {
        options.first { $0.kind == .rejectOnce } ?? options.first { $0.isRejection }
    }

    private var requestTitle: String {
        if call.kind == .switchMode {
            return planEntries.isEmpty
                ? "\(agentName) has a plan" : "\(agentName) has a plan: \(planEntries.count) steps"
        }
        return "\(agentName) wants to \(analysis?.action ?? call.title)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ApprovalScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(requestTitle)
                            .font(DS.Approval.titleFont).foregroundStyle(.dsTextPrimary)
                        Text(
                            analysis?.reason
                                ?? (call.kind == .switchMode ? call.title : "The agent asked for permission.")
                        )
                        .font(.dsBody).foregroundStyle(.dsTextTertiary)
                    }
                    if !planEntries.isEmpty {
                        ComposerPlanSection(
                            plan: PlanProgress(entries: planEntries), isWorking: false,
                            isExpanded: $planExpanded, presentation: .review, showMore: showMorePlan)
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
                    } else if call.kind == .switchMode,
                        case .object(let input) = call.rawInput, input.count == 1,
                        let proposal = input["plan"]?.stringValue, call.content.isEmpty, call.rawOutput == nil
                    {
                        // The permission proposal can differ from its progress checklist. Keep its
                        // exact words visible without exposing the surrounding wire-format object.
                        Text(verbatim: proposal).font(.dsBody).foregroundStyle(.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } else {
                        ToolCallBody(call: call, presentation: ToolPresentation(call), phase: ToolPhase(call))
                    }
                    if !isAvailable {
                        Text("Waiting for the task to reconnect before you can answer.")
                            .font(.dsBody).foregroundStyle(.dsTextSecondary)
                    }
                    if let policy = policy?.policy, policy.isManaged(.forbiddenPermissionModes) {
                        Label(
                            "Permission modes are managed by \(policy.organizationName ?? "your organization").",
                            systemImage: "lock"
                        )
                        .font(.dsBody).foregroundStyle(.dsTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
            .disabled(sending || committed || !isAvailable)
            if rejection != nil {
                Rectangle().fill(DS.Approval.separator(colorScheme)).frame(height: DS.Approval.rule)
                HStack(alignment: .bottom, spacing: DS.Space.md) {
                    ComposerEditor(
                        text: $instruction, selection: $instructionSelection,
                        placeholder: "Or tell \(agentName) what to do instead", isFocused: $instructionFocused,
                        inputLabel: "Tell \(agentName) what to do instead", insets: DS.Approval.editorInsets,
                        maximumHeight: DS.Approval.instructionMaximumHeight
                    ) { press in
                        guard !PlatformTextInput.isComposing else { return .ignored }
                        if press.key == .tab, press.modifiers.isSubset(of: [.shift]) {
                            return ComposerPlatform.moveKeyFocus(forward: !press.modifiers.contains(.shift))
                                ? .handled : .ignored
                        }
                        guard press.key == .return, press.modifiers.isEmpty else {
                            return .ignored
                        }
                        sendInstruction(instruction)
                        return .handled
                    }
                    .disabled(sending || committed || !isAvailable)
                    if openTask == nil || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ComposerSendButton(
                            disabledReason: instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Enter an instruction first" : nil
                        ) { sendInstruction(instruction) }
                        .accessibilityLabel("Ask \(agentName) to do this instead")
                        .disabled(sending || committed || !isAvailable)
                    }
                    taskLink
                }
                .padding(.horizontal, DS.Approval.inset)
                .padding(.vertical, DS.Space.lg)
                .frame(minHeight: DS.Approval.instructionHeight)
            } else if openTask != nil {
                taskLink.frame(maxWidth: .infinity, alignment: .trailing).padding(DS.Approval.inset)
            }
        }
        .onChange(of: focusRequested, initial: true) { _, requested in
            if requested { instructionFocused = true; didFocus() }
        }
        .onChange(of: responseAttempt) {
            // Retrying a choice resets only its hold, never the user's instruction draft.
            committed = false
            keyboardHeld = false
        }
        .approvalHoldKeys(
            enabled: shortcutsEnabled && legacyShortcut && isAvailable && !sending && !committed
                && analysis?.risk == .irreversible
        ) {
            keyboardHeld = $0
        }
    }

    @ViewBuilder private var taskLink: some View {
        if let openTask { AskOpenTaskLink(action: openTask) }
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
            Text(analysis?.suggestedExplanation ?? "Review the suggested alternative before running it.")
                .font(.dsBody).foregroundStyle(.dsTextSecondary)
        }
    }

    private func fixItButton(_ replacement: String) -> some View {
        Button("Ask \(agentName) to Use It") {
            sendInstruction("Don't run that. Run this instead:\n\(replacement)")
        }
        .buttonStyle(ApprovalActionStyle(small: true))
        .accessibilityLabel("Ask \(agentName) to Use the Suggested Command")
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
        ForEach(options.filter(\.isRejection)) { option in
            let ownsShortcut = option.kind == .rejectOnce && isFirst(option)
            Button {
                onChoose(option)
            } label: {
                actionLabel(optionTitle(option, ordinary: "Don't Allow"), keys: ownsShortcut ? "⌘⇧⌫" : "")
            }
            .buttonStyle(ApprovalActionStyle())
            .keyboardShortcut(
                shortcutsEnabled && ownsShortcut ? KeyboardShortcut(.delete, modifiers: [.command, .shift]) : nil)
        }
        if analysis?.risk != .irreversible {
            ForEach(options.filter { $0.kind == .allowAlways }) { option in
                Button {
                    onChoose(option)
                } label: {
                    actionLabel(
                        optionTitle(option, ordinary: "Always Allow"),
                        keys: options.first { $0.kind == .allowAlways }?.id == option.id ? "⌥⌘Y" : "")
                }
                .buttonStyle(ApprovalActionStyle())
                .keyboardShortcut(
                    shortcutsEnabled && options.first { $0.kind == .allowAlways }?.id == option.id
                        ? KeyboardShortcut("y", modifiers: [.command, .option]) : nil)
            }
        }
        ForEach(options.filter { $0.kind == .allowOnce }) { allow in
            let ownsShortcut = isFirst(allow)
            let canUseShortcut = shortcutsEnabled && legacyShortcut && ownsShortcut
            let title = optionTitle(allow, ordinary: "Allow")
            if analysis?.risk == .irreversible {
                ApprovalHoldButton(
                    shortcutsEnabled: canUseShortcut, keyboardHeld: ownsShortcut && keyboardHeld,
                    actionName: title == "Allow" ? nil : title, primary: ownsShortcut,
                    forceReducedMotion: forceReducedMotion,
                    didCommit: { committed = true }
                ) { onChoose(allow) }
                .id(responseAttempt)
            } else {
                Button {
                    onChoose(allow)
                } label: {
                    actionLabel(title, keys: canUseShortcut ? "⌘Y" : "")
                }
                .buttonStyle(ApprovalActionStyle(primary: ownsShortcut))
                .keyboardShortcut(canUseShortcut ? KeyboardShortcut("y", modifiers: .command) : nil)
            }
        }
    }

    private func isFirst(_ option: PermissionOption) -> Bool {
        options.first { $0.kind == option.kind }?.id == option.id
    }

    private func optionTitle(_ option: PermissionOption, ordinary: String) -> String {
        // A kind is a lifetime, not a decision: strict review, decline and cancel can share it.
        if call.kind == .switchMode || option.kind == .rejectAlways
            || options.filter({ $0.kind == option.kind }).count > 1
        {
            return option.name
        }
        return ordinary
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
                    command: ApprovalPreviewFixtures.commands[0], options: ApprovalPreviewFixtures.distinctOptions
                ).frame(width: 760)
                ApprovalPreviewFixtures.card(
                    command: ApprovalPreviewFixtures.commands[2], options: ApprovalPreviewFixtures.distinctOptions
                ).frame(width: 760)
                ApprovalPreviewFixtures.card(
                    command: ApprovalPreviewFixtures.commands[0],
                    failure: "Couldn't send your instruction. Your words are kept. Try again."
                ).frame(width: 760)
                ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0], sending: true)
                    .frame(width: 760)
                ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0], isAvailable: false)
                    .frame(width: 760)
            }.padding(DS.Space.xl)
        }.frame(height: 900)
    }
}
#Preview("Approval - global ask owns the shortcut") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0])
            ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[2])
        }
        .environment(\.legacyAskShortcutEnabled, false)
        .frame(width: 760)
        .padding(DS.Space.xl)
    }
}
#endif
