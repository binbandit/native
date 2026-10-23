#if DEBUG
import SwiftUI

/// Interactive fixture for checking the grid's transitions without starting an agent.
struct TaskSignalPreview: View {
    @State private var status = TaskStatus.working
    @State private var unread = false
    @State private var since: Date?
    @State private var reduceMotion = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text("Task signals").font(.dsTitle)
            HStack(spacing: DS.Space.xl) {
                TaskSignal(status: status, isUnread: unread, attentionSince: since)
                Text(status.label).font(.dsCallout)
                Button("Working") { status = .working }
                Button("New Ask") {
                    since = .now; status = .needsPermission
                }
                Button("Expiring Ask") {
                    since = .now.addingTimeInterval(-55); status = .needsPermission
                }
                Button("Old Ask") {
                    since = .now.addingTimeInterval(-120); status = .needsPermission
                }
                Button("Finished") {
                    unread = true; status = .done
                }
                Button("Read") { unread = false }
                Button("Failed") { status = .failed }
                Toggle("Reduce Motion", isOn: $reduceMotion)
            }
            Grid(alignment: .leading, horizontalSpacing: DS.Space.xxxl, verticalSpacing: DS.Space.lg) {
                GridRow {
                    Text("State")
                    Text("12pt")
                    Text("13pt")
                    Text("14pt")
                    Text("15pt")
                    Text("Reduce Motion")
                }
                .font(.dsBodyMedium)
                ForEach(TaskStatus.allCases, id: \.self) { state in
                    GridRow {
                        Text(state.label).font(.dsBody)
                        TaskSignal(status: state, isUnread: true, placement: .toolbarCount)
                        TaskSignal(status: state, isUnread: true, placement: .well)
                        TaskSignal(status: state, isUnread: true, placement: .sidebar)
                        TaskSignal(status: state, isUnread: true, placement: .peek)
                        TaskSignal(status: state, isUnread: true).environment(\.taskSignalReducedMotion, true)
                    }
                }
                GridRow {
                    Text("On build-mac, offline since 2:14 PM").font(.dsBody)
                    TaskSignal(status: .working, unavailable: "On build-mac, offline since 2:14 PM")
                }
            }
            Spacer()
        }
        .environment(\.taskSignalReducedMotion, reduceMotion)
        .padding(DS.Space.xxxl)
        .foregroundStyle(.dsTextPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.dsBackground)
    }
}

#Preview("Signals - Interactive transitions") {
    DSPreviewPair { TaskSignalPreview() }
}
#endif
