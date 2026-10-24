import ACP
import NativeHostProtocol
import SwiftUI

/// Every host, each with what needs you first, then what's working, then what finished. Hosts stay
/// in their own sections: nothing from one host mixes into another's.
struct HomeView: View {
    @Binding var selection: CompanionDestination?
    @Environment(CompanionStore.self) private var store
    @State private var needsYouOnly = false
    @State private var isShowingSettings = false
    @State private var isStartingTask = false

    private static let recentLimit = 5

    var body: some View {
        List(selection: $selection) {
            ForEach(visibleHosts) { host in
                HostSection(host: host, needsYouOnly: needsYouOnly, recentLimit: Self.recentLimit)
            }
        }
        .listStyle(.insetGrouped)
        .hostTint(store.activeHost?.preferences)
        .scrollContentBackground(.hidden)
        .background(.dsBackground)
        .navigationTitle("Tasks")
        .refreshable {
            for host in visibleHosts { await host.refresh() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HostChip(needsYouOnly: $needsYouOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    .accessibilityIdentifier("settings")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isStartingTask = true
            } label: {
                Label("New Task", systemImage: "plus")
                    .font(CompanionType.bodyMedium)
                    .foregroundStyle(.dsTextOnAccent)
                    .padding(.horizontal, DS.Space.xl)
                    .frame(minHeight: CompanionMetrics.pill)
            }
            .buttonStyle(.glassProminent)
            .padding(.bottom, DS.Space.md)
            .dsReservedRegionPadding()
            .accessibilityIdentifier("newTask")
        }
        .sheet(isPresented: $isStartingTask) {
            NewTaskSheet(preferredHost: store.activeHost?.id)
        }
        .sheet(isPresented: $isShowingSettings) {
            CompanionSettingsView()
        }
    }

    private var visibleHosts: [HostConnection] {
        store.hosts.filter { store.activeHostID == nil || $0.id == store.activeHostID }
    }
}

#if DEBUG
#Preview("Tasks - Compact and regular") {
    DSPreviewPair {
        CompanionLayoutPreview(selectedTask: false)
            .environment(\.horizontalSizeClass, .regular)
            .frame(width: 900, height: 760)
    }
}
#endif

/// One host's part of the home screen.
private struct HostSection: View {
    let host: HostConnection
    let needsYouOnly: Bool
    let recentLimit: Int

    var body: some View {
        let needsYou = host.sessions.filter(\.needsApproval)
        let working = host.sessions.filter { $0.isWorking && !$0.needsApproval }
        let rest = host.sessions.filter { !$0.isWorking && !$0.needsApproval }
        Section {
            NavigationLink(value: CompanionDestination.host(host.id)) {
                HostSummaryRow(host: host, needsYou: needsYou.count, working: working.count)
            }
            .accessibilityIdentifier("host-\(host.name)")
            if let detail = host.phase.detail(hostName: host.name) {
                Text(detail)
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsTextSecondary)
            }
            ForEach(needsYou) { session in
                NeedsYouRow(host: host, session: session)
            }
            if !needsYouOnly {
                ForEach(working) { session in
                    taskLink(session)
                }
                ForEach(rest.prefix(recentLimit)) { session in
                    taskLink(session)
                }
                if rest.count > recentLimit {
                    NavigationLink("All \(host.sessions.count) tasks", value: CompanionDestination.allTasks(host.id))
                        .font(CompanionType.subheadline)
                }
                if host.sessions.isEmpty, host.phase.isConnected {
                    Text(
                        "No tasks on \(host.name) yet. Start the first one on the Mac; then you can start more from here."
                    )
                    .font(CompanionType.subheadline)
                    .foregroundStyle(.dsTextSecondary)
                }
            }
        }
    }

    private func taskLink(_ session: HostSessionSummary) -> some View {
        NavigationLink(value: CompanionDestination.task(TaskRoute(hostID: host.id, sessionID: session.id))) {
            CompanionTaskRow(host: host, session: session)
        }
        .accessibilityIdentifier("task-\(host.name)")
    }
}

/// A host's line: its mark and name, connection, counts, and an available update.
struct HostSummaryRow: View {
    let host: HostConnection
    let needsYou: Int
    let working: Int

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            HostMark(preferences: host.preferences)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(host.name)
                    .font(CompanionType.headline)
                    .foregroundStyle(.dsTextPrimary)
                HostConnectionLine(host: host)
                if let release = host.update?.available, host.update?.hasInstallableUpdate == true {
                    Text("Update available · \(release.version)")
                        .font(CompanionType.captionMedium)
                        .foregroundStyle(.dsAccentText)
                }
            }
            Spacer()
            if needsYou > 0 {
                Badge("\(needsYou) needs you", tone: .attention, style: .soft)
            } else if working > 0 {
                Text("\(working) working")
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsTextSecondary)
            }
        }
        .padding(.vertical, DS.Space.xs)
    }
}

/// A task: its status, title, what it's doing, and how long ago.
struct CompanionTaskRow: View {
    let host: HostConnection
    let session: HostSessionSummary

    var body: some View {
        let mirror = host.mirrors[session.id]
        HStack(alignment: .top, spacing: DS.Space.lg) {
            StatusIndicator(status: session.taskStatus(mirror))
                .padding(.top, DS.Space.xxs)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(session.displayTitle(mirror))
                    .font(CompanionType.body)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(2)
                Text(session.statusLine(mirror))
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.md)
            if let lastActivity = session.lastActivity {
                Text(DSFormat.compactAge(lastActivity, now: .now))
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsTextTertiary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: DS.Size.minimumHitTarget)
        .accessibilityElement(children: .combine)
    }
}

/// Every task on one host.
struct HostTasksView: View {
    let host: HostConnection

    var body: some View {
        List(host.sessions) { session in
            NavigationLink(value: TaskRoute(hostID: host.id, sessionID: session.id)) {
                CompanionTaskRow(host: host, session: session)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.dsBackground)
        .navigationTitle(host.name)
    }
}
