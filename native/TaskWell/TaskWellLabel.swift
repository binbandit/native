import ACP
import SwiftUI

/// The capsule keeps its size across states. The agent gives way before the object's middle;
/// the trailing progress or Review never competes for the text's width.
struct TaskWellLabel: View {
    let content: TaskWellContent

    var body: some View {
        HStack(spacing: DS.TaskWell.gap) {
            StatusIndicator(status: content.status, size: DS.TaskWell.signal)
                .accessibilityHidden(true)
            headline
                .frame(maxWidth: .infinity, alignment: .leading)
            if content.progress != nil || content.showsReview {
                trailing
                    .padding(.leading, DS.TaskWell.dividerInset)
                    .overlay(alignment: .leading) {
                        SeparatorLine(axis: .vertical)
                            .frame(height: DS.TaskWell.signal)
                    }
                    .fixedSize()
            }
        }
        .font(DS.TaskWell.body)
        .padding(.leading, DS.TaskWell.leading)
        .padding(.trailing, DS.TaskWell.trailing)
        .frame(width: DS.TaskWell.width, height: DS.TaskWell.height)
        .dsGlassEffect(in: Capsule())
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityText)
    }

    @ViewBuilder private var headline: some View {
        if let outcome = content.outcome {
            HStack(spacing: DS.TaskWell.textGap) {
                Text("Changed \(outcome.changedFiles.count) \(outcome.changedFiles.count == 1 ? "file" : "files")")
                    .lineLimit(1)
                DiffStatsText(stats: DiffStats(added: outcome.linesAdded, removed: outcome.linesRemoved))
                    .font(DS.TaskWell.object)
                    .fixedSize()
                    .contentTransition(.numericText())
            }
        } else if content.verb.isEmpty {
            Text(content.agent)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            ViewThatFits(in: .horizontal) {
                narration(includesAgent: !content.isWaiting)
                    .fixedSize(horizontal: true, vertical: false)
                narration(includesAgent: false)
            }
        }
    }

    private func narration(includesAgent: Bool) -> some View {
        HStack(spacing: DS.TaskWell.textGap) {
            if includesAgent {
                Text(content.agent)
                    .foregroundStyle(.dsTextTertiary)
            }
            Text(content.verb)
                .foregroundStyle(content.isWaiting ? .dsTextPrimary : .dsTextSecondary)
                .fixedSize()
            if let object = content.object {
                Text(object)
                    .font(content.isWaiting ? .dsBody : DS.TaskWell.object)
                    .foregroundStyle(content.isWaiting ? .dsTextSecondary : .dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if let progress = content.progress {
            HStack(spacing: DS.TaskWell.textGap) {
                if progress.total <= DS.TaskWell.maxTicks {
                    HStack(spacing: DS.TaskWell.tickGap) {
                        ForEach(0..<progress.total, id: \.self) { index in
                            RoundedRectangle(cornerRadius: DS.TaskWell.tickRadius)
                                .fill(index < progress.completed ? .dsTextSecondary : .dsTextQuaternary)
                                .frame(width: DS.TaskWell.tickWidth, height: DS.TaskWell.tickHeight)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text("\(progress.completed) of \(progress.total)")
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .help("Plan steps completed")
            }
        } else if content.showsReview {
            Text("Review")
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextPrimary)
        }
    }
}

#if DEBUG
#Preview("Well - Every state") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ForEach(Array(TaskWellPreviewFixtures.states.enumerated()), id: \.offset) { _, content in
                TaskWellLabel(content: content)
            }
        }
        .padding(DS.Space.xl)
    }
}
#endif
