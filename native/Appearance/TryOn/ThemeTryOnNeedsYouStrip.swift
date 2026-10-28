import SwiftUI

/// The line at the top of Try On's list while tasks wait on the user. Choosing it ends Try On,
/// writing nothing, and opens the first of them.
struct ThemeTryOnNeedsYouStrip: View {
    let tasks: [SessionModel]
    let open: (SessionKey) -> Void
    @State private var isHovered = false

    var body: some View {
        if let first = tasks.first {
            Button {
                open(first.key)
            } label: {
                HStack(spacing: DS.TryOn.rowGap) {
                    TaskSignal(status: first.taskStatus, placement: .sidebar)
                    Text(tasks.count == 1 ? "1 task needs you" : "\(tasks.count) tasks need you")
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                }
                .padding(.horizontal, DS.Space.md)
                .frame(maxWidth: .infinity, minHeight: max(DS.TryOn.rowHeight, DS.Size.minimumHitTarget))
                .background(isHovered ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.row))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .trackHover($isHovered)
            .padding(.horizontal, DS.Space.md)
            .padding(.top, DS.Space.md)
            .accessibilityHint("Ends Try On and opens the task")
        }
    }
}
