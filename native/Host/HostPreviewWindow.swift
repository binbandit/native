import ACP
import NativeHostClient
import NativeHostProtocol
import ServiceManagement
import SwiftUI

/// Sessions that run in Native's background host, so they keep working after Native quits. The
/// Phase 1 preview of `docs/durability.md`: in Phase 2 every session works this way and this
/// window goes away.
struct HostPreviewWindow: View {
    static let id = "host-preview"

    @Environment(AppModel.self) private var model
    @State private var host = DurableHost()
    @State private var selection: HostSessionID?
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            SeparatorLine()
            if !host.isEnabled {
                EmptyStateView(
                    "Keep agents working after Native quits",
                    systemImage: "moon.zzz",
                    message: "Sessions here run in Native's background host. Quit Native, come back later, and the work is done. If the host or an agent stops, Native restarts it and resumes the task.",
                    actionTitle: "Turn On"
                ) {
                    Task { await host.setEnabled(true) }
                }
            } else {
                if !host.awayActivity.isEmpty {
                    awaySummary
                }
                HStack(spacing: 0) {
                    sessionList
                        .frame(width: DS.Size.sidebarWidth)
                    SeparatorLine(axis: .vertical)
                    detail
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .background(Color.dsBackground)
        .task {
            await host.start(agents: model.plugins.agents.map(Self.spec))
        }
        .alert("Durable Sessions", isPresented: isShowingError, presenting: host.errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            Text(connectionText)
                .font(.dsCaption)
                .foregroundStyle(Color.dsTextSecondary)
            Spacer()
            if case .failed(let reason) = host.registration {
                Text("The host didn't start: \(reason)")
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsDanger)
            }
            if case .needsApproval = host.registration {
                Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.ds(.secondary))
            }
            if host.isEnabled {
                Button("Stop Host and Agents") { Task { await host.stopHost() } }
                    .buttonStyle(.ds(.ghost))
                Button("Turn Off") { Task { await host.setEnabled(false) } }
                    .buttonStyle(.ds(.ghost))
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Window.headerHeight)
    }

    private var connectionText: String {
        switch host.connection {
        case nil: host.isEnabled ? "Starting the host…" : "Off"
        case .connecting: "Connecting…"
        case .connected(let info): "Connected to \(info.machineName) · host pid \(info.processID)"
        case .reconnecting(let attempt, _): attempt == 0 ? "Reconnecting…" : "Reconnecting (attempt \(attempt))…"
        case .unreachable(let reason): "The host isn't reachable: \(reason)"
        case .incompatible(let version): "The host speaks protocol \(version); restart it to update"
        }
    }

    private var awaySummary: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("While you were away").font(.dsCalloutMedium)
                    Spacer()
                    Button("Dismiss") { host.dismissAwayActivity() }.buttonStyle(.ds(.ghost))
                }
                ForEach(host.awayActivity) { entry in
                    Text(Self.describe(entry))
                        .font(.dsBody)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }
        }
        .padding(DS.Space.lg)
    }

    // MARK: - Sessions

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Menu("New Session") {
                ForEach(model.plugins.agents) { agent in
                    Button(agent.displayName) {
                        guard let cwd = model.currentProject?.url ?? model.projects.all.first?.url else { return }
                        Task { selection = await host.newSession(agent: agent.id.rawValue, cwd: cwd) ?? selection }
                    }
                }
            }
            .disabled(model.projects.all.isEmpty || !isConnected)
            .help(model.projects.all.isEmpty ? "Open a folder in Native first; sessions start in it." : "")
            .padding(DS.Space.md)
            ScrollView {
                VStack(spacing: DS.Space.xxs) {
                    ForEach(host.sessions) { session in
                        Button {
                            selection = session.id
                            Task { await host.attach(session.id) }
                        } label: {
                            HStack(spacing: DS.Space.md) {
                                StatusIndicator(status: Self.status(of: session))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(session.title ?? URL(filePath: session.cwd).lastPathComponent).font(.dsCallout).lineLimit(1)
                                    Text(session.agentName).font(.dsCaption).foregroundStyle(Color.dsTextTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, DS.Space.md)
                            .frame(height: DS.Size.controlMD)
                            .background(selection == session.id ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.Space.sm)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selection, let session = host.sessions.first(where: { $0.id == selection }) {
            VStack(spacing: 0) {
                ScrollView {
                    // Not lazy: a lazy stack anchored to the bottom kept re-measuring replayed rows and
                    // spun the main thread.
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        ForEach(host.mirrors[selection]?.state.items ?? []) { item in
                            transcriptItem(item, session: selection)
                        }
                    }
                    .frame(maxWidth: DS.Size.contentColumn)
                    .padding(DS.Space.xl)
                }
                .defaultScrollAnchor(.bottom)
                SeparatorLine()
                HStack(spacing: DS.Space.md) {
                    TextField("Message \(session.agentName)", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.dsCallout)
                        .onSubmit(send)
                    if session.isWorking {
                        Button("Stop") { Task { await host.cancel(selection) } }
                            .buttonStyle(.ds(.secondary))
                    }
                    Button(session.isWorking ? "Queue" : "Send", action: send)
                        .buttonStyle(.ds(.primary))
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(DS.Space.lg)
            }
        } else {
            EmptyStateView(
                host.sessions.isEmpty ? "No durable sessions yet" : "No session selected",
                systemImage: "rectangle.stack",
                message: host.sessions.isEmpty ? "Start one with New Session. It keeps running after you quit Native." : "Pick a session on the left."
            )
        }
    }

    @ViewBuilder private func transcriptItem(_ item: TranscriptItem, session: HostSessionID) -> some View {
        switch item {
        case .message(let message): MessageView(message: message)
        case .notice(let notice): NoticeView(notice: notice)
        case .toolCall(let call):
            ToolCallView(call: call) { option in
                Task { await host.choose(option, forToolCall: call.id, in: session) }
            }
        case .subagent(let subagent): Text(subagent.title ?? "Subagent").font(.dsBody).foregroundStyle(Color.dsTextSecondary)
        case .sessionMessage(let message): Text(message.text).font(.dsBody).foregroundStyle(Color.dsTextSecondary)
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding { host.errorMessage != nil } set: { isShowing in
            if !isShowing { host.errorMessage = nil }
        }
    }

    private var isConnected: Bool {
        if case .connected = host.connection { true } else { false }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, !text.isEmpty else { return }
        draft = ""
        Task { await host.send(text, to: selection) }
    }

    // MARK: - Mapping

    private static func spec(_ agent: AgentDefinition) -> AgentSpec {
        AgentSpec(
            id: agent.id.rawValue, name: agent.displayName, command: agent.manifest.command, args: agent.manifest.args,
            env: agent.manifest.env, resolveExecutables: agent.manifest.resolveExecutables
        )
    }

    private static func status(of session: HostSessionSummary) -> TaskStatus {
        if session.needsApproval { return .needsPermission }
        switch session.phase {
        case .prompting: return .working
        case .loading, .recovering: return .starting
        case .disconnected: return .failed
        case .idle, .unknown:
            return switch session.lastStopReason {
            case "end_turn": .done
            case "cancelled": .cancelled
            case "error": .failed
            default: .idle
            }
        }
    }

    private static func describe(_ entry: ActivityEntry) -> String {
        let time = entry.at.formatted(date: .omitted, time: .shortened)
        let subject = entry.subject ?? "A session"
        return switch entry.kind {
        case .turnFinished: "\(time) · \(subject) finished"
        case .turnFailed: "\(time) · \(subject) failed: \(entry.detail ?? "unknown error")"
        case .approvalNeeded: "\(time) · \(subject) needs approval: \(entry.detail ?? "a tool call")"
        case .recovered: "\(time) · \(entry.recovery?.sentence() ?? "Native recovered \(subject)")"
        case .hostStarted: "\(time) · \(entry.detail ?? "Native's host started")"
        case .unknown: "\(time) · \(subject)"
        }
    }
}
