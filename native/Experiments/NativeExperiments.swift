import Experiments

// Every experiment in Native is declared in this file and listed in `ExperimentCatalog.native`.
// The code an experiment changes reads it through `@Experiment` (gates, parameters) or `@Resolved`
// (extension points). See "Experiments" in docs/architecture.md.

extension ExperimentCatalog {
    /// In the order Labs lists them.
    static let native = ExperimentCatalog([
        Variant.bubbles,
        Parameter<TranscriptWidth>.transcriptWidth,
        Gate.unfoldExploration,
        Gate.sessionTools,
        Gate.taskWell,
        Gate.sidebarNext,
        Gate.composerNext,
        Gate.composeTask,
        Gate.changeAgent,
        Gate.coordinatorTasks,
        Gate.homeNext,
        Gate.settingsPlainly,
    ])
}

extension ExperimentStore {
    /// The user's experiments, saved in user defaults.
    static let shared = ExperimentStore(catalog: .native, storage: UserDefaultsExperimentStorage())
}

// MARK: - Variants

extension Variant {
    static let bubbles = Variant(
        id: "bubbles",
        title: "Bubbles",
        summary: "Show conversations as chat bubbles: your messages on the right, the agent's on the left, "
            + "with its tool activity in between.",
        stage: .labs,
        owner: "transcript",
        reviewBy: ReviewDate(year: 2027, month: 1, day: 31),
        claims: [Claim(.transcriptStyle, BubbleTranscriptStyle())]
    )
}

// MARK: - Parameters

extension Parameter where Value == TranscriptWidth {
    static var transcriptWidth: Self {
        Self(
            id: "transcript-width",
            title: "Transcript width",
            summary: "How wide the conversation and the composer can grow on a large window.",
            site: "Task ▸ column width",
            stage: .beta,
            owner: "transcript",
            reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
            default: .standard,
            domain: .allCases
        )
    }
}

// MARK: - Gates

extension Gate {
    static let composeTask = Gate(
        id: "NativeComposeTask",
        title: "Compose Task",
        summary: "Start a task from Quick Entry without leaving the task you're reading.",
        site: "New Task ▸ Quick Entry",
        stage: .labs,
        owner: "new-task",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
        default: false
    )

    static let coordinatorTasks = Gate(
        id: "coordinator-tasks", title: "Coordinator tasks",
        summary: "Align existing tasks with a coordinator that starts read-only in the project folder.",
        site: "File > New Coordinator Task and sidebar", stage: .labs, owner: "orchestration",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15), default: false
    )

    static let changeAgent = Gate(
        id: "change-agent", title: "Change Agent",
        summary:
            "Choose another agent above the model list in either composer. Keep the draft and undo the choice before sending.",
        site: "Task > Switch Agent", stage: .labs, owner: "tasks",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15), default: false
    )

    static let homeNext = Gate(
        id: "NativeHomeNext",
        title: "Next",
        summary: "Answer asks one at a time on Home, with the quickest decisions first.",
        site: "Home > Next",
        stage: .labs,
        owner: "home",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
        default: false
    )

    static let taskWell = Gate(
        id: "NativeTaskWell",
        title: "The well",
        summary: "One quiet place for task activity, requests, outcomes and tools in the toolbar.",
        site: "Task ▸ toolbar and tools",
        stage: .labs,
        owner: "tasks",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
        default: false
    )

    static let settingsPlainly = Gate(
        id: "NativeSettingsPlainly",
        title: "Plainly settings",
        summary: "A simpler page map, with one home for new-task defaults and related settings together.",
        site: "Settings",
        stage: .labs,
        owner: "settings",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
        default: false
    )

    static let sidebarNext = Gate(
        id: "NativeSidebarNext",
        title: "All in view",
        summary: "Titles at rest, shared signals, Peek and a global shortcut for the oldest ask.",
        site: "Sidebar ▸ projects and tasks",
        stage: .labs,
        owner: "sidebar",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
        default: false
    )

    static let composerNext = Gate(
        id: "NativeComposerNext",
        title: "Fine print",
        summary: "One field and settings popover, with explained approvals and deliberate confirmation.",
        site: "Composer ▸ field, settings and approvals",
        stage: .labs,
        owner: "composer",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
        default: false
    )

    static let unfoldExploration = Gate(
        id: "unfold-exploration",
        title: "Show every file read and search",
        summary: "List each read and search on its own row instead of folding runs into “Explored 3 files”.",
        site: "Transcript ▸ tool activity",
        stage: .labs,
        owner: "transcript",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15)
    )

    static let sessionTools = Gate(
        id: "session-tools",
        title: "Task tools",
        summary: "Shows live Changes facts under the task title, with Changes beside a wide conversation "
            + "or over a narrow one. Other task tools are still being built.",
        site: "Task ▸ header and tools",
        stage: .labs,
        owner: "tasks",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15)
    )
}
