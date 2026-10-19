import GitHub
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// The Open as Task sheet, over the window whenever a pull request is being opened as a task.
    func pullRequestTaskSheet(_ opener: PullRequestTaskOpener, app: AppModel, gitHub: GitHubModel) -> some View {
        sheet(isPresented: Binding(get: { opener.request != nil }, set: { if !$0 { opener.cancel() } })) {
            if let request = opener.request {
                PullRequestTaskSheet(opener: opener, request: request)
                    .environment(app)
                    .environment(gitHub)
            }
        }
    }
}

/// Opening a pull request as a task: what will happen (which project, which branch, whether it
/// can push), then progress, then the task. Also where a missing project is cloned, an existing
/// task is updated, and failures say what to do.
struct PullRequestTaskSheet: View {
    let opener: PullRequestTaskOpener
    let request: PullRequestTaskOpener.Request

    @Environment(AppModel.self) private var app
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            SeparatorLine()
            content
            if hasFooter {
                SeparatorLine()
                footer
            }
        }
        .frame(width: PullRequestTaskSheetLayout.width)
        .background(.dsBackground)
        .interactiveDismissDisabled(!opener.canCancel)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { opener.chooseCloneFolder(folder) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(headline)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                if let reference = request.reference {
                    Text(verbatim: "Open \(reference.display) as a task")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            Spacer(minLength: DS.Space.lg)
            IconButton("Close", systemImage: "xmark") { opener.cancel() }
                .keyboardShortcut(.cancelAction)
                .disabled(!opener.canCancel)
        }
        .padding(.leading, DS.Space.xl)
        .padding(.trailing, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .frame(minHeight: DS.Window.headerHeight + DS.Space.md)
    }

    private var headline: String {
        if case .picking = request.phase { return "Open Pull Request as Task" }
        return request.title ?? request.reference?.display ?? "Open as Task"
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch request.phase {
        case .picking:
            PullRequestTaskPicker(opener: opener)
        case .resolving:
            progress("Looking up the pull request…")
        case .ready(let checkout):
            PullRequestTaskReadyView(
                checkout: checkout, agent: app.defaultAgent?.displayName,
                includesReviewComments: Binding(
                    get: { opener.includesReviewComments }, set: { opener.includesReviewComments = $0 }))
        case .existing(let task):
            NoticeBanner(
                tone: .info, systemImage: "arrow.triangle.2.circlepath",
                title: "“\(task.title)” already works on this pull request",
                detail:
                    "The pull request has new commits since the task checked it out. Updating fast-forwards the task's branch to them; if the task's own commits or changes are in the way, Native leaves the task as it is and says so."
            )
            .padding(DS.Space.xl)
        case .needsClone(let missing, let folder, let state):
            PullRequestTaskCloneView(missing: missing, folder: folder, state: state) { isChoosingFolder = true }
        case .working(let step):
            progress(step.label)
        case .failed(let problem):
            ErrorState(
                problem.title, recovery: problem.recovery, suggestion: problem.suggestion, details: problem.details,
                primary: action(problem.primary), secondary: problem.secondary.map(action), layout: .pane
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progress(_ label: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            DotGridLoader(pattern: .waiting)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
            Text(label)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func action(_ action: PullRequestTaskProblem.Action) -> ErrorState.Action {
        let title =
            switch action {
            case .retry: "Try Again"
            case .openTask: "Open Task"
            case .chooseFolder: "Choose Another Folder"
            }
        return ErrorState.Action(title) { opener.perform(action) }
    }

    // MARK: - Footer

    private var hasFooter: Bool {
        switch request.phase {
        case .ready, .existing, .needsClone, .working(.cloning): true
        case .picking, .resolving, .working, .failed: false
        }
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: DS.Space.md) {
            switch request.phase {
            case .ready:
                Spacer()
                cancelButton
                primaryButton("Open as Task", enabled: true)
            case .existing:
                Spacer()
                cancelButton
                Button("Open Without Updating") { opener.openWithoutUpdating() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                primaryButton("Update and Open", enabled: true)
            case .needsClone(_, _, let state):
                Spacer()
                cancelButton
                primaryButton(
                    state == .checkout ? "Add Project and Open" : "Clone and Open",
                    enabled: state == .free || state == .checkout)
            default:
                Text("Large repositories take a while to clone.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                Spacer()
                cancelButton
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
    }

    private var cancelButton: some View {
        Button("Cancel") { opener.cancel() }
            .buttonStyle(.ds(.ghost, size: .medium))
    }

    private func primaryButton(_ title: String, enabled: Bool) -> some View {
        Button(title) { opener.confirm() }
            .buttonStyle(.ds(.primary, size: .medium))
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
    }
}

enum PullRequestTaskSheetLayout {
    static let width: CGFloat = 560
    /// The picker's list, tall enough for about eight pull requests.
    static let pickerHeight: CGFloat = 360
    /// The label column of the sheet's facts.
    static let labelWidth: CGFloat = 64
}
