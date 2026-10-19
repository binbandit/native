import ProjectActions
import SwiftUI

/// A background run's output, for Show Output: what ran where, how it ended, and everything it
/// printed (the end of it, for a very long run), selectable and copyable.
struct ProjectActionOutputSheet: View {
    let run: ProjectActionBackgroundRun
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text("\(run.action.command) · \(run.directory.abbreviatedPath)")
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ScrollView {
                Text(output.isEmpty ? "It printed nothing." : output)
                    .font(.dsMono)
                    .foregroundStyle(output.isEmpty ? .dsTextTertiary : .dsTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.md)
            }
            // Long output opens on its end, where failures usually are; short output reads from the top.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(.dsBorder, lineWidth: 1)
            }
            HStack {
                Button("Copy Output") { DSPasteboard.copy(output) }
                    .buttonStyle(.ds(.secondary))
                    .disabled(output.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: ProjectActionMetrics.outputSheetWidth, height: ProjectActionMetrics.outputSheetHeight)
    }

    private var title: String {
        switch run.result {
        case .finished(let outcome, _)?: outcome.summary(of: run.action.name)
        case .failedToStart(let reason)?: "\(run.action.name) couldn't run: \(reason)"
        case nil: "\(run.action.name) is running"
        }
    }

    private var output: String {
        if case .finished(_, let output)? = run.result { output } else { "" }
    }
}
