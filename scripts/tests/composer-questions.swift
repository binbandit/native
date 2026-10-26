import ACP
import Foundation

@testable import Native

@main
@MainActor
private struct ComposerQuestionChecks {
    static func main() throws {
        let red = AgentQuestionnaire.Option(value: "Red", title: "Red (Recommended)", description: nil)
        let blue = AgentQuestionnaire.Option(value: "Blue", title: "Blue", description: nil)
        let plain = try questionnaire(custom: false, multiple: false)
        guard let question = plain.questions.first else { throw MissingQuestion() }
        var answers = AgentQuestionnaireAnswers(suggesting: plain)
        require(answers.isPicked(red, in: question), "The recommended single choice starts picked")
        answers.type("Blue", for: question)
        require(answers.content(for: plain) == ["color": .string("Blue")], "Typing replaces a suggested pick")
        answers.choose(red, in: question)
        answers.type("Blue", for: question)
        require(answers.content(for: plain) == ["color": .string("Blue")], "Typing replaces an explicit pick")
        answers.choose(red, in: question)
        require(answers.content(for: plain) == ["color": .string("Red")], "Picking replaces typed text")
        answers.clear(question)
        answers.type(" \n\t ", for: question)
        require(!answers.isAnswered(question), "Whitespace is not an answer")
        require(answers.content(for: plain).isEmpty, "Whitespace is not sent")

        let companion = try questionnaire(custom: true, multiple: false)
        guard let withNote = companion.questions.first else { throw MissingQuestion() }
        answers = AgentQuestionnaireAnswers(suggesting: companion)
        answers.type("teal", for: withNote)
        require(answers.content(for: companion) == ["color_custom": .string("teal")], "Words replace a suggestion")
        answers.choose(red, in: withNote)
        require(
            answers.content(for: companion) == ["color": .string("Red"), "color_custom": .string("teal")],
            "An explicit choice can carry a companion note")

        let multiple = try questionnaire(custom: false, multiple: true)
        guard let several = multiple.questions.first else { throw MissingQuestion() }
        answers = AgentQuestionnaireAnswers(suggesting: multiple)
        require(answers.content(for: multiple).isEmpty, "Multi-select suggestions are not picked for the user")
        answers.choose(red, in: several)
        answers.choose(blue, in: several)
        require(
            answers.content(for: multiple) == ["color": .array([.string("Red"), .string("Blue")])],
            "Multi-select keeps both choices")
        answers.choose(red, in: several)
        require(answers.content(for: multiple) == ["color": .array([.string("Blue")])], "Picking again toggles off")
        print("PASS: suggested and explicit picks, typed replacements, companion notes, whitespace and multi-select")
    }

    private static func questionnaire(custom: Bool, multiple: Bool) throws -> AgentQuestionnaire {
        let options: JSONValue = .array([
            .object(["const": .string("Red"), "title": .string("Red (Recommended)")]),
            .object(["const": .string("Blue"), "title": .string("Blue")]),
        ])
        let select: JSONValue = .object(["type": .string("string"), "oneOf": options])
        var properties: [String: JSONValue] = [
            "color": multiple ? .object(["type": .string("array"), "items": select]) : select
        ]
        if custom { properties["color_custom"] = .object(["type": .string("string")]) }
        guard
            let questionnaire = AgentQuestionnaire(
                message: "Which color?", schema: .object(["properties": .object(properties)]))
        else {
            throw MissingQuestion()
        }
        return questionnaire
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    private struct MissingQuestion: Error {}
}
