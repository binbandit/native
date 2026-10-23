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
        Gate.sidebarNext,
        Gate.composerNext,
        Gate.composeTask,
        Gate.homeNext,
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

    static let sidebarNext = Gate(
        id: "NativeSidebarNext",
        title: "Quiet projects",
        summary: "A calmer sidebar with monospace project names, marks for active tasks and folded older tasks.",
        site: "Sidebar ▸ projects and tasks",
        stage: .labs,
        owner: "sidebar",
        reviewBy: ReviewDate(year: 2026, month: 12, day: 15),
        default: false
    )

    static let composerNext = Gate(
        id: "NativeComposerNext",
        title: "Quiet composer",
        summary: "Show the resting composer's settings as a line of words, each opening its picker.",
        site: "Composer ▸ resting settings",
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
