import ACP
import SwiftUI

/// An agent's questions docked above the draft: one
/// question at a time with a pager, options as rows with a line of detail, a free-text row, and
/// Skip / Next. Its keys are in docs/keyboard.md, "Agent questions".
struct AgentQuestionSection: View {
    let questionnaire: AgentQuestionnaire
    /// Takes focus on appear, when nothing else in the composer is in progress.
    let takesFocus: Bool
    let onSubmit: ([String: JSONValue]) -> Void
    /// Declines every question; the agent hears that the user skipped them.
    let onSkipAll: () -> Void

    private enum Field: Hashable {
        case card, text
    }

    @State private var index = 0
    @State private var answers = AgentQuestionnaireAnswers()
    @State private var highlighted = 0
    @FocusState private var focus: Field?

    private var question: AgentQuestionnaire.Question {
        questionnaire.questions[index]
    }

    private var isLast: Bool {
        index == questionnaire.questions.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            header
            Text(question.prompt)
                .font(.dsCalloutMedium)
                .foregroundStyle(.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !question.options.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { offset, option in
                        row(option, number: offset + 1)
                    }
                }
            }
            TextField(question.options.isEmpty ? "Your answer" : "Or type your own answer", text: typedText)
                .textFieldStyle(.plain)
                .font(.dsBody)
                .focused($focus, equals: .text)
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: DS.Size.listRow)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(.dsBorder)
                }
                .onSubmit(advance)
            footer
        }
        .padding(DS.Space.md)
        .focusable()
        .focused($focus, equals: .card)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKey)
        .onAppear {
            if takesFocus { focus = .card }
        }
        .onChange(of: index) { highlighted = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Question \(index + 1) of \(questionnaire.questions.count)")
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Text(question.header ?? "Question")
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
            Spacer()
            if questionnaire.questions.count > 1 {
                pagerButton("Previous Question", systemImage: "chevron.left", isEnabled: index > 0) { index -= 1 }
                Text(verbatim: "\(index + 1)/\(questionnaire.questions.count)")
                    .font(.dsBody)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
                pagerButton("Next Question", systemImage: "chevron.right", isEnabled: !isLast) { index += 1 }
            }
            pagerButton("Skip All Questions", systemImage: "xmark", isEnabled: true, action: onSkipAll)
        }
    }

    private func pagerButton(
        _ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .frame(width: DS.Size.listRow - DS.Space.md, height: DS.Size.listRow - DS.Space.md)
            .contentShape(.rect)
            .disabled(!isEnabled)
            .help(title)
    }

    private func row(_ option: AgentQuestionnaire.Option, number: Int) -> some View {
        let isPicked = answers.isPicked(option, in: question)
        return Button {
            pick(option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                Kbd("\(number)")
                    .opacity(number <= 9 ? 1 : 0)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(option.title)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextPrimary)
                    if let description = option.description {
                        Text(description)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(
                    systemName: question.allowsMultiple ? (isPicked ? "checkmark.square.fill" : "square") : "checkmark"
                )
                .font(.dsCaption)
                .foregroundStyle(isPicked ? .dsAccentText : .dsTextTertiary)
                .opacity(question.allowsMultiple || isPicked ? 1 : 0)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(minHeight: DS.Size.listRow)
            .background(
                rowFill(isPicked: isPicked, isHighlighted: number - 1 == highlighted),
                in: .rect(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { highlighted = number - 1 }
        }
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func rowFill(isPicked: Bool, isHighlighted: Bool) -> Color {
        if isPicked {
            .dsSelected
        } else if isHighlighted && focus == .card {
            .dsHover
        } else {
            .clear
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.sm) {
            Spacer()
            Button("Skip") { skip() }
                .buttonStyle(.ds(.ghost))
                .help("Leave this question unanswered")
            Button(isLast ? "Send Answers" : "Next") { advance() }
                .buttonStyle(.ds(.primary))
                .help("Return")
        }
    }

    private var typedText: Binding<String> {
        let key = AgentQuestionnaireAnswers.textKey(for: question)
        return Binding(get: { answers.typed[key, default: ""] }, set: { answers.typed[key] = $0 })
    }

    // MARK: - Actions

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Typing in the text field must stay typing, and ⌘1–9, ⌥⌘↑/↓ and the like belong to the app.
        guard focus == .card, press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        let options = question.options
        if let digit = press.characters.first?.wholeNumberValue, (1...9).contains(digit), digit <= options.count {
            highlighted = digit - 1
            pick(options[digit - 1])
            return .handled
        }
        switch press.key {
        case .upArrow:
            highlighted = max(highlighted - 1, 0)
        case .downArrow:
            highlighted = min(highlighted + 1, max(options.count - 1, 0))
        case .space where options.indices.contains(highlighted):
            pick(options[highlighted])
        case .return:
            advance()
        default:
            return .ignored
        }
        return .handled
    }

    private func pick(_ option: AgentQuestionnaire.Option) {
        answers.pick(option, in: question)
    }

    private func skip() {
        answers.clear(question)
        advance()
    }

    private func advance() {
        if isLast {
            onSubmit(answers.content(for: questionnaire))
        } else {
            index += 1
            focus = .card
        }
    }
}

#if DEBUG
#Preview("Agent question") {
    ComposerSurface {
        if let questionnaire = AgentQuestionnaire.preview {
            AgentQuestionSection(questionnaire: questionnaire, takesFocus: true, onSubmit: { _ in }, onSkipAll: {})
        }
    }
    .padding()
    .frame(width: 640)
}
#endif
