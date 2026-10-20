import SwiftUI

/// Workbench: the project at the top of the page as a compact header (its icon, name, where the task
/// works and the actions to run there), a line of facts (setup, the checkout, GitHub), then short
/// lists to pick up from instead of starting fresh: the latest tasks and the pull requests waiting
/// on the user. The composer stays below for new work.
struct NewSessionWorkbenchView: View {
    let context: NewSessionContext

    @State private var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            NewSessionWorkbenchFacts(context: context)
                .padding(.top, DS.Space.lg)
            SeparatorLine()
                .padding(.vertical, DS.Space.xl)
            lists
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: Bool.self) {
            $0.size.width < NewSessionMetrics.compactWidth
        } action: {
            isCompact = $0
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            ProjectAvatar(name: context.projectName, icon: context.projectIcon, size: NewSessionMetrics.headerIcon)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(context.projectName)
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                NewSessionWorkspaceLine(
                    workspace: context.workspace, projectName: context.projectName, size: .compact)
            }
            Spacer(minLength: DS.Space.lg)
            if !isCompact {
                actions
            }
        }
    }

    /// Up to three of the project's actions, to run in this task's folder; Add Action… before any.
    @ViewBuilder private var actions: some View {
        if context.actions.isEmpty {
            Button("Add Action…", systemImage: "plus", action: context.editActions)
                .buttonStyle(.ds(.ghost))
        } else {
            HStack(spacing: DS.Space.sm) {
                ForEach(context.actions.prefix(NewSessionMetrics.listLimit)) { action in
                    Button(action.name, systemImage: action.isRunning ? "stop.fill" : action.icon, action: action.run)
                        .buttonStyle(.ds(.secondary))
                        .help(action.isRunning ? "\(action.name) is running" : "Run \(action.command) in this task")
                }
            }
        }
    }

    @ViewBuilder private var lists: some View {
        let tasks = context.tasks.prefix(NewSessionMetrics.listLimit)
        let pullRequests = context.pullRequests.prefix(NewSessionMetrics.listLimit)
        if tasks.isEmpty, pullRequests.isEmpty {
            NewSessionWorkbenchNothingYet(context: context)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                if !tasks.isEmpty {
                    section("Continue a task", count: context.tasks.count) {
                        ForEach(tasks) { task in
                            NewSessionTaskRow(task: task, showsDetail: !isCompact)
                        }
                    }
                }
                if !pullRequests.isEmpty {
                    section(
                        context.repository.map { "Pull requests in \($0)" } ?? "Pull requests",
                        count: context.pullRequests.count
                    ) {
                        ForEach(pullRequests) { pullRequest in
                            NewSessionPullRequestRow(pullRequest: pullRequest, showsDetail: !isCompact)
                        }
                    }
                }
            }
        }
    }

    private func section(_ title: String, count: Int, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Text(title)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                Text("\(count)")
                    .foregroundStyle(.dsTextTertiary)
                    .monospacedDigit()
            }
            .font(.dsBodyMedium)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                rows()
            }
            // Rows' text lines up with the header's; their fills reach a little past it.
            .padding(.horizontal, -DS.Space.sm)
        }
    }
}

/// The header's facts: how the worktree's setup went, the project's uncommitted changes, and the
/// repository on GitHub. Each shows only when there's something to say.
private struct NewSessionWorkbenchFacts: View {
    let context: NewSessionContext

    var body: some View {
        FlowLayout(spacing: DS.Space.lg) {
            if let setup = context.setup {
                fact("Setup", setup.summary, tone: setup.tone)
            }
            if context.checkoutChanges > 0, context.workspace.isIsolated {
                fact(
                    "Checkout",
                    context.checkoutChanges == 1
                        ? "1 uncommitted change stays there"
                        : "\(context.checkoutChanges) uncommitted changes stay there")
            } else if context.checkoutChanges > 0 {
                fact("Checkout", "\(context.checkoutChanges) uncommitted to start with")
            }
            if let repository = context.repository {
                fact("GitHub", repository)
            }
            if case .folder = context.workspace {
                fact("Tasks", "share this folder")
            }
        }
    }

    private func fact(_ label: String, _ value: String, tone: Color = .dsTextSecondary) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(label)
                .foregroundStyle(.dsTextTertiary)
            Text(value)
                .foregroundStyle(tone)
                .monospacedDigit()
        }
        .font(.dsBody)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The lists' empty state: nothing to pick up yet, why, and that the composer is where to start.
private struct NewSessionWorkbenchNothingYet: View {
    let context: NewSessionContext

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Nothing to pick up in \(context.projectName) yet")
                .font(.dsCalloutMedium)
                .foregroundStyle(.dsTextSecondary)
            Text(reason)
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reason: String {
        let tasks = "Tasks you start here show up to continue from"
        return switch context.workspace {
        case .folder: "\(tasks). Pull requests do once it's a git repository on GitHub. Write below to start the first."
        case .worktree, .checkout, .unknown:
            context.repository == nil
                ? "\(tasks), and pull requests once the repository is on GitHub. Write below to start the first."
                : "\(tasks), with pull requests that wait on you. Write below to start the first."
        }
    }
}

extension NewSessionContext.Setup {
    /// "Done in 4s", "Running", "Waiting for you": the same words as the setup banner's.
    var summary: String {
        switch self {
        case .waiting: "Waiting for you to allow it"
        case .running: "Running"
        case .done(let seconds): seconds.map { "Done in \(DSFormat.duration($0))" } ?? "Done"
        case .failed(let phrase): phrase.prefix(1).uppercased() + phrase.dropFirst()
        }
    }

    var tone: Color {
        switch self {
        case .waiting: .dsAttention
        case .running, .done: .dsTextSecondary
        case .failed: .dsDanger
        }
    }
}
