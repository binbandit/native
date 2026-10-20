import NativeHostClient
import SwiftUI

/// "While you were away": what agents did while Native was closed, as a calm card above the detail
/// column. One row per task, those waiting on the user first; a row opens its task. It stays until
/// dismissed or every task in it has been opened.
struct HostAwayCard: View {
    let summary: AwaySummary
    /// The task's title as the sidebar shows it, or nil to use the host's.
    var title: (AwaySummary.Item) -> String?
    /// Opens the task; nil when it isn't in the sidebar anymore (archived, deleted).
    var open: (AwaySummary.Item) -> (() -> Void)?
    var onDismiss: () -> Void

    @State private var showsAll = false

    /// Rows before "Show all", so a long absence doesn't push the window's content far down.
    private static let collapsedRows = 4

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.top, DS.Space.md)
                    .padding(.bottom, summary.items.isEmpty ? DS.Space.md : DS.Space.sm)
                if !summary.items.isEmpty {
                    SeparatorLine()
                    VStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            HostAwayRow(item: item, title: title(item) ?? item.subject, open: open(item))
                        }
                        if summary.items.count > Self.collapsedRows {
                            Button(showsAll ? "Show Fewer" : "Show All \(summary.items.count) Tasks") {
                                withAnimation(.dsDisclosure) { showsAll.toggle() }
                            }
                            .buttonStyle(.ds(.ghost, size: .small))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.xs)
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("While you were away")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Image(systemName: "moon.zzz")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: DS.Size.rowLeading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text("While you were away")
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Text("since \(DSFormat.time(summary.since, now: .now))")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
                Text(summary.headline)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .buttonStyle(.ds(.ghost, iconOnly: true))
                .help("Dismiss")
        }
    }

    private var visibleItems: ArraySlice<AwaySummary.Item> {
        showsAll ? summary.items[...] : summary.items.prefix(Self.collapsedRows)
    }
}

/// One task in the card: its status, title, what happened and when. The whole row opens the task.
private struct HostAwayRow: View {
    let item: AwaySummary.Item
    let title: String
    let open: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button {
            open?()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                StatusIndicator(status: status)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(title)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(outcome)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: DS.Space.md)
                Text(DSFormat.time(item.at, now: .now))
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: max(DS.Size.listRow, DS.Size.minimumHitTarget))
            .background(isHovered && open != nil ? Color.dsHover : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(open == nil)
        .trackHover($isHovered)
        .help(open == nil ? "This task isn't in the sidebar anymore." : "Open \(title)")
        .accessibilityLabel("\(title), \(outcome)")
    }

    private var status: TaskStatus {
        switch item.outcome {
        case .needsApproval: .needsPermission
        case .asked: .needsInput
        case .failed: .failed
        case .finished: .done
        case .working: .working
        }
    }

    private var outcome: String {
        switch item.outcome {
        case .needsApproval(let tool): tool.map { "Needs your approval: \($0)" } ?? "Needs your approval"
        case .asked(let question): question.map { "Asked: \($0)" } ?? "Has a question for you"
        case .failed(let reason): reason.map { "Failed: \($0)" } ?? "Failed"
        case .finished: item.recoveries.isEmpty ? "Finished" : "Finished after Native resumed it"
        case .working: "Working again after Native resumed it"
        }
    }
}
