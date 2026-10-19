import SwiftUI

/// A task on its way in, in the detail column: what it's waiting for right now and for how long,
/// or why it couldn't start, above a composer that takes the first message meanwhile. A message
/// sent before the session exists goes out the moment it does.
struct StartingTaskView: View {
    let task: StartingTask

    @Environment(AppModel.self) private var model
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let failure = task.failure, failure.canUseProjectFolder {
                    ErrorState(
                        failure.title,
                        suggestion: failure.message,
                        primary: ErrorState.Action("Start in Project Folder") {
                            Task { await model.startInProjectFolder(task) }
                        },
                        secondary: ErrorState.Action("Retry") { Task { await model.retry(task) } },
                        layout: .pane
                    )
                } else if let failure = task.failure {
                    ErrorState(
                        failure.title,
                        recovery: failure.needsSignIn
                            ? nil : "What you've written is kept, and so is anything already set up for the task.",
                        suggestion: failure.needsSignIn ? failure.message : "Retry, or discard the task.",
                        details: failure.needsSignIn ? nil : failure.message,
                        primary: failure.needsSignIn
                            ? ErrorState.Action("Sign In") { model.signInPrompt = task.agent.id }
                            : ErrorState.Action("Retry") { Task { await model.retry(task) } },
                        secondary: ErrorState.Action("Discard") { model.discard(task) },
                        layout: .pane
                    )
                } else {
                    StartingTaskProgress(task: task)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            StartingTaskComposer(task: task)
                .frame(maxWidth: columnWidth.maxWidth)
                .padding(.horizontal, DS.Space.xxl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xl)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("New Session")
        .navigationSubtitle(model.projects.project(task.project)?.url.abbreviatedPath ?? "")
    }
}

/// The steps a starting task goes through, the one it's on animated, with the time it's taken.
private struct StartingTaskProgress: View {
    let task: StartingTask

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            VStack(spacing: DS.Space.xs) {
                Text("Starting a \(task.agent.displayName) session")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                HStack(spacing: DS.Space.xs) {
                    Text("\(task.stepLabel)…")
                    Text("·")
                    ElapsedTimeText(since: task.startedAt)
                }
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                row(task.workspaceLabel, done: task.folder != nil, isCurrent: task.step == .preparingWorkspace)
                row(
                    "Starting \(task.agent.displayName)", done: task.isAgentReady,
                    isCurrent: task.step == .startingAgent)
                row("Opening the session", done: false, isCurrent: task.step == .openingSession)
            }
            Text("Write your first message below. It goes out as soon as the session is ready.")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.xxl)
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, done: Bool, isCurrent: Bool) -> some View {
        HStack(spacing: DS.Space.sm) {
            StatusIndicator(status: done ? .done : isCurrent ? .starting : .idle)
            Text(title)
                .font(.dsCallout)
                .foregroundStyle(done || isCurrent ? .dsTextPrimary : .dsTextTertiary)
        }
    }
}

/// The starting task's composer: the draft carries over to the session, and Return sends it there
/// once the session exists. Shift-Return and Option-Return make a new line.
private struct StartingTaskComposer: View {
    @Bindable var task: StartingTask

    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        ComposerSurface(isFloating: true) {
            if task.isSendRequested {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "clock")
                        .foregroundStyle(.dsTextTertiary)
                    Text("Sends when the session is ready")
                        .foregroundStyle(.dsTextSecondary)
                    Spacer(minLength: 0)
                    Button("Don't Send") { task.isSendRequested = false }
                        .buttonStyle(.ds(.ghost))
                }
                .font(.dsCaption)
                .padding(.horizontal, DS.Composer.textInsets.leading)
                .padding(.vertical, DS.Space.xs)
            }
            HStack(alignment: .bottom, spacing: 0) {
                ComposerEditor(
                    text: $task.draft, selection: $selection,
                    placeholder: "What would you like \(task.agent.displayName) to work on?", isFocused: $isFocused
                ) { press in
                    guard press.key == .return, press.modifiers.isDisjoint(with: [.shift, .option]) else {
                        return .ignored
                    }
                    send()
                    return .handled
                }
                if !task.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !task.isSendRequested {
                    ComposerSendButton(action: send)
                        .padding(DS.Space.md)
                }
            }
            .frame(minHeight: DS.Size.composerInputMinHeight)
            // Where the session's controls go, so the composer keeps its height when they arrive.
            HStack(spacing: DS.Composer.controlSpacing) {
                AgentIcon(agent: task.agent)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                Text(task.agent.displayName)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: DS.Space.sm)
                Text("Model and settings once the session is ready")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            }
            .frame(minHeight: DS.Size.composerPill)
            .padding(DS.Composer.controlsInset)
        }
        .onAppear(perform: takeFocusIfWanted)
        .onChange(of: task.wantsComposerFocus) { takeFocusIfWanted() }
    }

    private func send() {
        guard !task.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        task.isSendRequested = true
    }

    private func takeFocusIfWanted() {
        guard task.wantsComposerFocus else { return }
        isFocused = true
        task.wantsComposerFocus = false
    }
}
