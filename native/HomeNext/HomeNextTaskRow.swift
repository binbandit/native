import SwiftUI

struct HomeNextTaskRow: View {
    let task: HomeNextTask
    var finished = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.lg) {
                StatusIndicator(status: finished ? .idle : task.status)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(task.title)
                        .font(finished ? .dsCallout : .dsCalloutMedium)
                        .foregroundStyle(finished ? .dsTextSecondary : .dsTextPrimary)
                    if !finished {
                        Text(task.ask).font(.dsBody).foregroundStyle(.dsTextSecondary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if finished, let diff = task.diff {
                    Text(diff).font(.dsMonoCaption).foregroundStyle(.dsTextTertiary)
                }
                Group {
                    if finished, let date = task.finishedAt {
                        Text(date.formatted(date: .omitted, time: .shortened))
                    } else if let date = task.date {
                        DSMinuteTimeline { now in Text(DSFormat.compactAge(date, now: now)) }
                    }
                }
                .font(.dsCaption).foregroundStyle(.dsTextTertiary).monospacedDigit().fixedSize()
            }
            .padding(.vertical, finished ? 0 : DS.HomeNext.rowInset)
            .frame(minHeight: finished ? DS.HomeNext.finishedHeight : DS.HomeNext.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .dsHitTarget(finished ? DS.HomeNext.finishedHeight : DS.HomeNext.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the task")
        .help([task.title, task.ask].joined(separator: "\n"))
    }
}

#if DEBUG
#Preview("Next row - Asks and finished") { HomeNextPreviewFixtures.page(.busy) }
#endif
