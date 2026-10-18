import ACP
import NativeHostProtocol
import SwiftUI

/// One task: its transcript (folded with the same `SessionState` reducer as the Mac), what it's
/// doing now, an approval docked at the bottom when it waits on you, and the composer otherwise.
struct TaskView: View {
    let host: HostConnection
    let sessionID: HostSessionID

    @State private var stopFailure: String?
    @State private var selectedCall: ToolCallState?

    var body: some View {
        if let session = host.summary(sessionID) {
            content(session, mirror: host.mirrors[sessionID])
        } else {
            EmptyStateView(
                "This task is gone", systemImage: "tray",
                message: "It was closed on \(host.name). Its history stays with the agent.")
        }
    }

    private func content(_ session: HostSessionSummary, mirror: SessionMirror?) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.lg) {
                if mirror == nil || mirror?.isLoading == true {
                    HStack(spacing: DS.Space.md) {
                        DotGridLoader(pattern: .settingUp)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                        Text("Loading the conversation from \(host.name)…")
                            .font(CompanionType.subheadline).foregroundStyle(.dsTextSecondary)
                    }
                }
                ForEach(mirror?.state.items ?? []) { item in
                    CompanionTranscriptRow(item: item, answers: host.answers) { selectedCall = $0 }
                }
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: CompanionMetrics.readableWidth, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .background(.dsBackground)
        .safeAreaInset(edge: .top, spacing: 0) {
            banner(session)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottom(session, mirror: mirror)
        }
        .navigationTitle(session.displayTitle(mirror))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(session.displayTitle(mirror)).font(CompanionType.captionMedium).foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                    HStack(spacing: DS.Space.xs) {
                        Text("\(session.agentName) · \(session.projectName) ·").lineLimit(1)
                        HostMark(preferences: host.preferences, size: CompanionMetrics.hostMarkTiny)
                        Text(host.name).lineLimit(1).layoutPriority(1)
                    }
                    .font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
                    .accessibilityElement(children: .combine)
                }
            }
            if session.isWorking {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stop", systemImage: "stop.fill") {
                        Task { stopFailure = await host.cancel(sessionID) }
                    }
                    .accessibilityIdentifier("stop")
                }
            }
        }
        .sheet(item: $selectedCall) { call in
            ToolCallDetailSheet(call: call)
        }
        .hostTint(host.preferences)
        .onAppear { host.attach(sessionID) }
    }

    @ViewBuilder
    private func banner(_ session: HostSessionSummary) -> some View {
        if !host.phase.isConnected {
            NoticeBanner(
                tone: .warning, title: host.phase.title,
                detail: host.phase.detail(hostName: host.name) ?? "The agent keeps working on \(host.name)."
            )
            .padding(DS.Space.md)
        } else if let stopFailure {
            NoticeBanner(tone: .danger, title: "Couldn't stop it", detail: stopFailure).padding(DS.Space.md)
        } else if session.isWorking {
            HStack(spacing: DS.Space.md) {
                StatusIndicator(status: session.taskStatus(host.mirrors[sessionID]))
                Text(session.statusLine(host.mirrors[sessionID]))
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                Spacer()
                if let since = session.lastActivity {
                    ElapsedTimeText(since: since).font(CompanionType.caption).foregroundStyle(.dsTextTertiary)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func bottom(_ session: HostSessionSummary, mirror: SessionMirror?) -> some View {
        if let pending = mirror?.state.pendingPermissions.first {
            ApprovalCard(
                host: host, sessionID: sessionID, toolCallID: pending.toolCallID, permission: pending.permission,
                call: mirror?.state.toolCall(id: pending.toolCallID)
            )
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.sm)
            // The card is content, not a floating control: the transcript stops behind it.
            .background(.dsBackground)
        } else {
            VStack(spacing: DS.Space.sm) {
                if !session.queue.isEmpty {
                    QueuedMessagesView(host: host, session: session)
                }
                CompanionComposer(host: host, session: session)
            }
            .padding(.top, DS.Space.sm)
        }
    }
}

extension ToolCallState: @retroactive Identifiable {}

/// Messages waiting for the running turn to end: send one now, or take it back.
private struct QueuedMessagesView: View {
    let host: HostConnection
    let session: HostSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(session.queue) { item in
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "clock").foregroundStyle(.dsTextTertiary)
                    Text(item.text).lineLimit(1).foregroundStyle(.dsTextPrimary)
                    Spacer()
                    Button("Send Now") { Task { _ = await host.sendQueuedNow(item.id, in: session.id) } }
                        .font(CompanionType.caption)
                    Button("Remove", systemImage: "xmark") {
                        Task { _ = await host.removeQueued(item.id, in: session.id) }
                    }
                    .labelStyle(.iconOnly)
                    .dsHitTarget(DS.Size.composerAction)
                }
                .font(CompanionType.subheadline)
            }
            if session.isQueuePaused {
                Text("Paused after the last turn stopped. Your next message continues the queue.")
                    .font(CompanionType.caption).foregroundStyle(.dsTextTertiary)
            }
        }
        .padding(DS.Space.md)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        .padding(.horizontal, DS.Space.lg)
    }
}
