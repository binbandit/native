#if DEBUG && NATIVE_SESSION_CHROME_WIP
import ProjectActions
import SwiftUI
import Terminal

/// The project's actions as a pane: each with its command and how its last run went, Run or Stop,
/// and the way to its output, which lives in the task's terminal.
struct SessionChromeRunPane: View {
    let context: SessionChromeContext
    let showOutput: (ProjectAction) -> Void

    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        if let target = context.target {
            let actions = context.runner.store.list(for: target.project).all
            if actions.isEmpty {
                EmptyStateView(
                    "No actions for \(target.project.name) yet", systemImage: "play",
                    message: "Actions are the project's quick commands, like Test or Dev, run in this task's folder."
                ) {
                    Button("Add Action…") { settings.open(.project(target.project.id)) }
                        .buttonStyle(.ds(.secondary))
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(actions) { action in
                            row(action, in: target)
                            SeparatorLine()
                        }
                        Button("Edit Actions…") { settings.open(.project(target.project.id)) }
                            .buttonStyle(.ds(.ghost))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.md)
                    }
                }
            }
        } else {
            EmptyStateView(
                "No project", systemImage: "play",
                message: "Actions belong to a project, and this task isn't in one.")
        }
    }

    private func row(_ action: ProjectAction, in target: ProjectActionTarget) -> some View {
        let state = context.runner.state(of: action, in: target)
        let hasOutput = context.terminal.tabs.tab(forJob: action.id.rawValue) != nil
        return HStack(spacing: DS.Space.md) {
            Image(systemName: action.icon ?? "play")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.rowLeading)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    Text(action.name)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    status(state)
                }
                Text(action.command)
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.md)
            if hasOutput {
                Button("Output") { showOutput(action) }
                    .buttonStyle(.ds(.ghost))
            }
            if state?.isRunning == true {
                Button(state?.isStopping == true ? "End Now" : "Stop") { context.runner.stop(action, in: target) }
                    .buttonStyle(.ds(.secondary))
            } else {
                Button("Run") { context.runner.run(action, in: target) }
                    .buttonStyle(.ds(.secondary))
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    @ViewBuilder private func status(_ state: ProjectActionRunState?) -> some View {
        switch state {
        case .running(let since, _)?:
            HStack(spacing: DS.Space.xs) {
                DotGridLoader(pattern: .waiting)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                ElapsedTimeText(since: since)
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextSecondary)
        case .some(let state) where state.hasFailed:
            HStack(spacing: DS.Space.xs) {
                StatusDot(color: .dsDanger)
                Text("Failed")
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextSecondary)
        case .finished?, .couldNotStart?, nil:
            EmptyView()
        }
    }
}
#endif
