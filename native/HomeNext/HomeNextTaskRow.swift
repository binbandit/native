import SwiftUI

struct HomeNextTaskRow: View {
    let task: HomeNextTask
    var finished = false
    let action: () -> Void

    var body: some View {
        HomeNextRow(
            status: finished ? .done : task.status, title: task.title, detail: finished ? nil : task.ask,
            date: finished ? nil : task.date, finishedAt: finished ? task.finishedAt : nil,
            diff: finished ? task.diff : nil, action: action
        )
        .accessibilityHint("Opens Peek without leaving Home")
    }
}

/// One line of Home's lists: a task, or a summary the user chose to add (reviews, a usage limit).
/// A row without detail is a finished task, drawn smaller.
struct HomeNextRow: View {
    let status: TaskStatus
    let title: String
    var detail: String?
    /// When it started waiting: the signal's attention and the row's age.
    var date: Date?
    var finishedAt: Date?
    var diff: String?
    /// A summary's signal borrows the status vocabulary for its color only; its words are the row's.
    var describesStatus = true
    let action: () -> Void

    private var finished: Bool { detail == nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.lg) {
                TaskSignal(status: status, placement: .sidebar, attentionSince: date)
                    .accessibilityHidden(!describesStatus)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                        .font(finished ? .dsCallout : .dsCalloutMedium)
                        .foregroundStyle(finished ? .dsTextSecondary : .dsTextPrimary)
                    if let detail {
                        Text(detail).font(.dsBody).foregroundStyle(.dsTextSecondary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let diff {
                    Text(diff).font(.dsMonoCaption).foregroundStyle(.dsTextTertiary)
                }
                Group {
                    if let finishedAt {
                        Text(finishedAt.formatted(date: .omitted, time: .shortened))
                    } else if let date {
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
        .help([title, detail].compactMap(\.self).joined(separator: "\n"))
    }
}

#if DEBUG
#Preview("Next row - Asks and finished") { HomeNextPreviewFixtures.page(.busy) }
#Preview("Next row - Review requests and a usage limit") { HomeNextPreviewFixtures.page(.summaries) }
#endif
