import ACP
import SwiftUI

/// An agent's question in the approval's frame: one question at a time, its choices on digit keys,
/// and the composer's field below for an answer in the user's own words. Hosts supply the
/// questionnaire and answer it; this view never talks to a connection. Keys are in docs/keyboard.md,
/// "Agent questions".
struct AnnotatedQuestionView: View {
    let agentName: String
    /// Nil for a question with nothing to fill in: the agent's message, to continue past or skip.
    let questionnaire: AgentQuestionnaire?
    let message: String
    var takesFocus = true
    var isAvailable = true
    var focusRequested = false
    var didFocus: () -> Void = {}
    /// For hosts away from the task (Home): "Open Task" at the field's trailing edge.
    var openTask: (() -> Void)?
    /// The side margin. A host whose column already has one (Home) passes 0, so the field's rule
    /// spans the column rather than overhanging it.
    var inset = DS.Approval.inset
    /// Answers already given, for previews of a picked choice.
    var initialAnswers: AgentQuestionnaireAnswers?
    let onSubmit: ([String: JSONValue]) async -> Void
    let onDecline: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var index = 0
    @State private var answers = AgentQuestionnaireAnswers()
    @State private var highlighted = 0
    @State private var sending = false
    @State private var wordsSelection: TextSelection?
    @FocusState private var cardFocused: Bool
    @FocusState private var wordsFocused: Bool

    private var questions: [AgentQuestionnaire.Question] { questionnaire?.questions ?? [] }
    private var question: AgentQuestionnaire.Question? { questions.indices.contains(index) ? questions[index] : nil }
    private var isLast: Bool { index >= questions.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(question?.prompt ?? message)
                    .font(DS.Approval.titleFont).foregroundStyle(.dsTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Approval.questionTitleTop)
                    .padding(.bottom, DS.Approval.questionTitleBottom)
                if let question, !question.options.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(question.options.enumerated()), id: \.element.id) { offset, option in
                            row(option, number: offset + 1, in: question)
                        }
                    }
                    .disabled(sending || !isAvailable)
                }
                if !isAvailable {
                    Text("Waiting for the task to reconnect before you can answer.")
                        .font(.dsBody).foregroundStyle(.dsTextSecondary)
                        .padding(.top, DS.Approval.footerTop)
                }
                footer.padding(.top, DS.Approval.footerTop)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, DS.Approval.askTop)
            .focusable(isAvailable)
            .focused($cardFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down, action: handleKey)
            if question != nil {
                Rectangle().fill(DS.Approval.separator(colorScheme)).frame(height: DS.Approval.rule)
                ownWords
            }
        }
        .onAppear {
            answers = initialAnswers ?? AgentQuestionnaireAnswers(suggesting: questionnaire)
            highlighted = question.map { answers.initialHighlight(in: $0) } ?? 0
            if takesFocus, isAvailable { cardFocused = true }
        }
        .onChange(of: focusRequested, initial: true) { _, requested in
            if requested, question != nil { wordsFocused = true; didFocus() }
        }
        .onChange(of: index) { highlighted = question.map { answers.initialHighlight(in: $0) } ?? 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            questions.count > 1 ? "\(agentName) asks, question \(index + 1) of \(questions.count)" : "\(agentName) asks"
        )
    }

    private var header: some View {
        HStack(spacing: DS.Space.xs) {
            Text("\(agentName) asks").font(.dsBody).foregroundStyle(.dsTextTertiary)
            Spacer(minLength: DS.Space.md)
            if questions.count > 1 {
                Text(verbatim: "\(index + 1) of \(questions.count)")
                    .font(.dsBody).monospacedDigit().foregroundStyle(.dsTextTertiary)
                pagerButton("Previous Question", systemImage: "chevron.left", isEnabled: index > 0) { index -= 1 }
                pagerButton("Next Question", systemImage: "chevron.right", isEnabled: !isLast) { index += 1 }
            }
        }
    }

    private func pagerButton(
        _ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly).buttonStyle(.plain)
            .font(.dsCaptionMedium)
            .foregroundStyle(isEnabled ? Color.dsTextSecondary : .dsTextQuaternary)
            .dsHitTarget(DS.Approval.smallButtonHeight)
            .disabled(!isEnabled)
            .help(title)
    }

    private func row(
        _ option: AgentQuestionnaire.Option, number: Int, in question: AgentQuestionnaire.Question
    )
        -> some View
    {
        let isPicked = answers.isPicked(option, in: question)
        let label = AgentQuestionOptionLabel(option.title)
        return Button {
            highlighted = number - 1
            answers.choose(option, in: question)
        } label: {
            HStack(alignment: .top, spacing: DS.Approval.optionGap) {
                keycap(number, isPicked: isPicked).opacity(number <= 9 ? 1 : 0)
                VStack(alignment: .leading, spacing: DS.Approval.optionDetailGap) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                        Text(label.title).font(.dsCallout).foregroundStyle(.dsTextPrimary)
                        if label.isRecommended {
                            Text("Recommended").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                        }
                    }
                    if let description = option.description {
                        Text(description).font(.dsBody).foregroundStyle(.dsTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Approval.optionInset)
            .padding(.vertical, DS.Space.md)
            .background(rowFill(isPicked: isPicked, number: number), in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -DS.Approval.optionInset)
        .onHover { if $0 { highlighted = number - 1 } }
        .accessibilityLabel(label.isRecommended ? "\(label.title), recommended" : label.title)
        .accessibilityHint(option.description ?? "")
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func keycap(_ number: Int, isPicked: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control)
        return Text(verbatim: "\(number)")
            .font(DS.Approval.keycapFont)
            .foregroundStyle(isPicked ? Color.dsTextOnAccent : .dsTextSecondary)
            .frame(width: DS.Approval.keycapSize, height: DS.Approval.keycapSize)
            .background(isPicked ? Color.dsAccent : .clear, in: shape)
            .overlay { if !isPicked { shape.strokeBorder(.dsBorderInner, lineWidth: DS.Approval.rule) } }
            .accessibilityHidden(true)
    }

    private func rowFill(isPicked: Bool, number: Int) -> Color {
        if isPicked { return .dsSelected }
        return number - 1 == highlighted && cardFocused ? .dsHover : .clear
    }

    private var footer: some View {
        HStack(spacing: DS.Space.sm) {
            // A confirmation has no field, so the link leads its buttons.
            if question == nil, let openTask { AskOpenTaskLink(action: openTask) }
            Spacer(minLength: 0)
            Group {
                if question == nil {
                    Button("Skip") { decline() }.buttonStyle(ApprovalActionStyle(quiet: true))
                    Button {
                        submit()
                    } label: {
                        actionLabel("Continue")
                    }
                    .buttonStyle(ApprovalActionStyle(primary: true))
                } else {
                    Button("Skip") { skip() }
                        .buttonStyle(ApprovalActionStyle(quiet: true))
                        .help("Leave this question unanswered")
                    Button {
                        submit()
                    } label: {
                        actionLabel(isLast ? (questions.count == 1 ? "Answer" : "Send Answers") : "Next")
                    }
                    .buttonStyle(ApprovalActionStyle(primary: true))
                }
            }
            .disabled(sending || !isAvailable)
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(title)
            Text(verbatim: "↩").font(.dsMonoMicro).opacity(DS.Approval.hintOpacity)
        }
    }

    private var ownWords: some View {
        HStack(alignment: .bottom, spacing: DS.Space.md) {
            Group {
                ComposerEditor(
                    text: typedText, selection: $wordsSelection, placeholder: "Or answer in your own words",
                    isFocused: $wordsFocused, inputLabel: "Answer \(agentName) in your own words",
                    insets: DS.Approval.editorInsets, maximumHeight: DS.Approval.instructionMaximumHeight
                ) { press in
                    guard press.key == .return, press.modifiers.isEmpty, !PlatformTextInput.isComposing else {
                        return .ignored
                    }
                    submit()
                    return .handled
                }
                if openTask == nil || !typedAnswer.isEmpty {
                    ComposerSendButton(disabledReason: typedAnswer.isEmpty ? "Type an answer first" : nil) {
                        submit()
                    }
                    .accessibilityLabel("Send Your Answer")
                }
            }
            .disabled(sending || !isAvailable)
            // The task stays a click away while the answer can't be sent.
            if let openTask { AskOpenTaskLink(action: openTask) }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, DS.Space.lg)
        .frame(minHeight: DS.Approval.instructionHeight)
    }

    private var typedAnswer: String {
        question.map { answers.typedAnswer(for: $0) } ?? ""
    }

    private var typedText: Binding<String> {
        let key = question.map { AgentQuestionnaireAnswers.textKey(for: $0) } ?? ""
        return Binding(
            get: { answers.typed[key, default: ""] },
            set: { text in
                if let question { answers.type(text, for: question) }
            })
    }

    // MARK: - Actions

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // ⌘1–9 and the like belong to the app; typing in the field stays typing.
        guard cardFocused, !sending, isAvailable, press.modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return .ignored
        }
        let options = question?.options ?? []
        if let digit = press.characters.first?.wholeNumberValue, (1...9).contains(digit), digit <= options.count,
            let question
        {
            highlighted = digit - 1
            answers.choose(options[digit - 1], in: question)
            return .handled
        }
        switch press.key {
        case .upArrow: highlighted = max(highlighted - 1, 0)
        case .downArrow: highlighted = min(highlighted + 1, max(options.count - 1, 0))
        case .space where options.indices.contains(highlighted):
            if let question { answers.choose(options[highlighted], in: question) }
        case .return: submit()
        default: return .ignored
        }
        return .handled
    }

    private func skip() {
        if let question { answers.clear(question) }
        submit()
    }

    private func submit() {
        guard !sending, isAvailable else { return }
        if questionnaire != nil, !isLast {
            index += 1
            cardFocused = true
            return
        }
        let content = questionnaire.map { answers.content(for: $0) } ?? [:]
        send { await onSubmit(content) }
    }

    private func decline() {
        guard !sending, isAvailable else { return }
        send(onDecline)
    }

    private func send(_ work: @escaping () async -> Void) {
        sending = true
        Task {
            await work()
            sending = false
        }
    }
}

/// Claude Code marks its suggested choice by ending the label "(Recommended)"; that becomes a tag.
struct AgentQuestionOptionLabel: Equatable {
    let title: String
    let isRecommended: Bool

    init(_ label: String) {
        let suffix = " (Recommended)"
        if label.hasSuffix(suffix), label.count > suffix.count {
            title = String(label.dropLast(suffix.count))
            isRecommended = true
        } else {
            title = label
            isRecommended = false
        }
    }
}

#if DEBUG
#Preview("Question - choices, picked, several, free text, confirmation, reconnecting, narrow") {
    DSPreviewPair {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                AskPreviewFixtures.question()
                AskPreviewFixtures.question(picked: 0)
                AskPreviewFixtures.question(AskPreviewFixtures.severalChoices, picked: 1)
                AskPreviewFixtures.question(AskPreviewFixtures.freeText)
                AskPreviewFixtures.question(nil, message: "Ready to apply the store migration?")
                AskPreviewFixtures.question(isAvailable: false)
                AskPreviewFixtures.question().frame(width: 420)
            }
            .frame(width: 808)
            .padding(DS.Space.xl)
        }
        .frame(height: 900)
    }
}
#endif
