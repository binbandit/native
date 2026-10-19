import Foundation

extension Mode.ID {
    public static let build: Self = "build"
    public static let plan: Self = "plan"
    public static let ask: Self = "ask"
    public static let debug: Self = "debug"
    public static let review: Self = "review"
}

extension Mode {
    /// Native's own modes, in the order the picker lists them. Build is the default: no
    /// instructions, and the task's settings as they are.
    public static let builtIn: [Mode] = [build, plan, ask, debug, review]

    public static let build = Mode(
        id: .build, name: "Build", symbol: "hammer",
        summary: "Works as the agent normally does, with your settings as they are",
        instructions: "", source: .builtIn)

    /// Uses the agent's own plan mode where it has one, so these instructions go only to agents
    /// without one (kept read-only meanwhile).
    public static let plan = Mode(
        id: .plan, name: "Plan", symbol: "list.bullet.clipboard",
        summary: "Plans first and changes nothing until you approve the plan",
        instructions: """
            Plan before changing anything.

            - Read the code you need, and work out what has to change and why.
            - Reply with a plan: the steps in order, the files each one touches, the risks, and how you'll check the result.
            - Ask about anything you'd otherwise have to guess.
            - Don't edit files or run commands that change anything. Wait for the user to approve the plan; they'll switch modes or tell you to go ahead.
            """,
        settings: ModeSettings(usesPlanMode: true), source: .builtIn)

    /// What Plan tells an agent whose own plan mode is on: that mode carries the rest.
    static let agentPlanInstructions =
        "Your own plan mode is on: research, present a plan, and change nothing until the user approves it."

    public static let ask = Mode(
        id: .ask, name: "Ask", symbol: "questionmark.bubble",
        summary: "Answers questions about the code and explains it, without editing",
        instructions: """
            Answer the user's questions about the code, and explain it. Don't change anything.

            - Read and search as much as you need, and point at code as `path:line`.
            - Explain plainly what the code does, why, and how the pieces connect. When you're not sure, say so rather than guess.
            - Don't edit files or run commands that change anything (installs, builds that write files, git commits). If answering would take a change, describe the change instead of making it.
            """,
        settings: ModeSettings(autonomy: .readOnly), source: .builtIn)

    public static let debug = Mode(
        id: .debug, name: "Debug", symbol: "ladybug",
        summary: "Reproduces the problem first, finds the root cause, then fixes and verifies it",
        instructions: """
            Find and fix the root cause of the problem the user describes, in this order:

            1. Reproduce it first, as close as you can to how the user hits it (end to end where possible). Say exactly how you reproduced it, or why you couldn't, before going further.
            2. Find the root cause. Follow the evidence (logs, a debugger, bisecting, temporary logging) rather than guessing, and explain the cause before you change anything.
            3. Write a test that fails because of the bug, where the project has tests.
            4. Fix the cause, not the symptom, with the smallest change that does it.
            5. Verify: the new test passes, your reproduction no longer fails, and the project's other tests still pass. Remove any temporary logging.

            Finish with the cause, the fix, and how you verified it.
            """,
        source: .builtIn)

    public static let review = Mode(
        id: .review, name: "Review", symbol: "text.magnifyingglass",
        summary: "Reviews the current changes and reports findings by severity, without editing",
        instructions: """
            Review the current changes. Don't edit anything unless the user asks.

            - Find what changed: uncommitted work (`git status`, `git diff`, `git diff --staged`) and the branch's commits against its base (`git merge-base HEAD origin/HEAD`, or the default branch, then `git diff <base>...HEAD`). If there's nothing to review, say so.
            - Read enough of the surrounding code to judge each change in context.
            - Report findings ranked by severity (Critical, High, Medium, Low), each with `path:line`, what's wrong, why it matters, and a suggested fix. Correctness, security and data loss come first; then behavior changes, missing tests and maintainability. Skip style a formatter would catch.
            - If you find nothing serious, say so plainly and list what you checked.
            - Don't change files, commit or push. If the user asks you to fix something, fix just that.
            """,
        settings: ModeSettings(autonomy: .readOnly), source: .builtIn)
}
