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
        HStack(spacing: DS.Space.sm) {
            Button {
                isShowingDetails = true
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.dsCaption)
                        .foregroundStyle(.dsWarning)
                        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                        .accessibilityHidden(true)
                    Text(problem.title)
                        .font(.dsCalloutBook)
                        .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.Size.rowMinHeight)
                .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .trackHover($isHovered)
            .help("\(problem.title). \(problem.recovery)")
            .accessibilityHint("Shows what went wrong")

            if model.isRetrying(problem) {
                DotGridLoader(pattern: .waiting)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(minWidth: DS.Size.controlXS)
                    .accessibilityLabel("Retrying")
            } else {
                Button("Retry") { retry() }
                    .buttonStyle(.ds(.ghost))
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
                primary: .init("Retry") {
                    isShowingDetails = false
                    retry()
                },
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
            Button("Retry") { retry() }
            Button("Show Details") { isShowingDetails = true }
            Button("Copy Error") { DSPasteboard.copy(problem.details) }
            Divider()
            Button("Dismiss") { model.dismiss(problem) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Retry") { retry() }
            Button("Dismiss") { model.dismiss(problem) }
        }
    }

    private func retry() {
        Task { await model.retry(problem) }
    }
}
