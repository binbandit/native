import Foundation

/// What the on-device model is told when it titles a task from its first message. Titling has no
/// package of its own, so its prompt lives with the instructions it takes.
public enum SessionTitlePrompt {
    /// Long prompts are trimmed; the start of a request says what it's about, and the on-device
    /// model's context is small.
    public static let requestLimit = 2_000

    public static let builtIn =
        "You title tasks in a coding agent app's sidebar so the user can find them later. Title what the user wants done, not what was said about it. A title is 2 to 6 words, on one line, without quotes or trailing punctuation."

    public static func instructions(adding addition: AIInstructionAddition?) -> String {
        AIInstructionAddition.applying(addition, to: builtIn)
    }

    public static func prompt(projectName: String, request: String) -> String {
        "Project: \(projectName)\nUser's request:\n\(request.prefix(requestLimit))"
    }
}
