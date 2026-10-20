import SwiftUI

/// A project's problem (`ProjectProblem`) in its sidebar section: a quiet row lined up with the
/// task rows, saying what failed, with Retry. Clicking or tapping it shows the whole failure the
/// one way failures show (`ErrorState`): what Native did about it, the error itself, Retry and
/// Dismiss.
struct ProjectProblemRow: View {
    @Environment(AppModel.self) private var model
    let problem: ProjectProblem

    @State private var isShowingDetails = false
    @State private var isHovered = false

    var body: some View {
        let isRetrying = model.isRetrying(problem)
        HStack(spacing: DS.Space.sm) {
            Button {
                isShowingDetails = true
            } label: {
                // Spaced like `TaskRow`, so the glyph and title line up with the task rows'.
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.dsCaption)
                        .foregroundStyle(.dsWarning)
                        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                        .padding(.top, DS.Space.xxs)
                        .padding(.trailing, DS.Space.xxs)
                        .accessibilityHidden(true)
                    Text(problem.title)
                        .font(.dsCalloutBook)
                        .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                        // A narrow sidebar wraps it rather than cutting off what failed.
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.md)
                .frame(minHeight: DS.Size.rowMinHeight)
                .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .trackHover($isHovered)
            .help("\(problem.title). \(problem.recovery)")
            .accessibilityHint("Shows what went wrong")

            // While retrying, the loader takes the button's place without moving the title.
            Button("Retry") { retry() }
                .buttonStyle(.ds(.ghost))
                .opacity(isRetrying ? 0 : 1)
                .disabled(isRetrying)
                .overlay {
                    if isRetrying {
                        DotGridLoader(pattern: .waiting)
                            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                            .foregroundStyle(.dsTextTertiary)
                            .accessibilityLabel("Retrying")
                    }
                }
        }
        .padding(.leading, TaskRowIndent.grouped.leading)
        .padding(.trailing, DS.Space.sm)
        .dsPopover(isPresented: $isShowingDetails, arrowEdge: .trailing) {
            ErrorState(
                problem.title,
                recovery: problem.recovery,
                suggestion: problem.suggestion,
                details: problem.details,
                primary: primaryAction,
                secondary: .init("Dismiss") {
                    isShowingDetails = false
                    model.dismiss(problem)
                },
                layout: .pane
            )
            .frame(width: DS.Size.popoverWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
        .contextMenu {
            if let alternative = problem.alternative {
                Button(alternative.title) { Task { await model.takeAlternative(of: problem) } }
            }
            Button("Retry") { retry() }
            Button("Show Details") { isShowingDetails = true }
            if let details = problem.details {
                Button("Copy Error") { DSPasteboard.copy(details) }
            }
            Divider()
            Button("Dismiss") { model.dismiss(problem) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if let alternative = problem.alternative {
                Button(alternative.title) { Task { await model.takeAlternative(of: problem) } }
            }
            Button("Retry") { retry() }
            Button("Dismiss") { model.dismiss(problem) }
        }
    }

    /// What the details lead with: the problem's other way forward where Retry alone won't help.
    private var primaryAction: ErrorState.Action {
        guard let alternative = problem.alternative else {
            return .init("Retry") {
                isShowingDetails = false
                retry()
            }
        }
        return .init(alternative.title) {
            isShowingDetails = false
            Task { await model.takeAlternative(of: problem) }
        }
    }

    private func retry() {
        Task { await model.retry(problem) }
    }
}

#if DEBUG
#Preview("Project problem") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let project = app.previewProject(1) {
            ProjectProblemRow(problem: SidebarPreviewFixtures.listingProblem(in: project))
                .frame(width: DS.Size.sidebarWidth)
        }
    }
    .sidebarPreviewEnvironment(app)
}
#endif
