import NativeHostProtocol
import SwiftUI

/// Starting a task on a host: which host, which agent and project (from what the host already
/// runs), and the first message. The task opens here and shows on the Mac without taking focus.
struct NewTaskSheet: View {
    let preferredHost: HostID?

    @Environment(CompanionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var hostID: HostID?
    @State private var agentID: String?
    @State private var cwd: String?
    @State private var prompt = ""
    @State private var isStarting = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                if store.hosts.count > 1 {
                    Picker("Host", selection: $hostID) {
                        ForEach(store.hosts) { host in
                            Text(host.name).tag(Optional(host.id))
                        }
                    }
                }
                if let host {
                    if agents(host).isEmpty {
                        Text("\(host.name) hasn't run a task yet, so this phone doesn't know its agents and projects. Start the first task on the Mac.")
                            .font(CompanionType.subheadline)
                            .foregroundStyle(.dsTextSecondary)
                    } else {
                        Picker("Agent", selection: $agentID) {
                            ForEach(agents(host), id: \.id) { agent in
                                Text(agent.name).tag(Optional(agent.id))
                            }
                        }
                        Picker("Project", selection: $cwd) {
                            ForEach(projects(host), id: \.self) { path in
                                Text(URL(filePath: path).lastPathComponent).tag(Optional(path))
                            }
                        }
                        Section("Message") {
                            TextField("What should it do?", text: $prompt, axis: .vertical)
                                .lineLimit(4...10)
                                .accessibilityIdentifier("newTaskPrompt")
                        }
                    }
                    if !host.phase.isConnected {
                        Text(host.phase.detail(hostName: host.name) ?? host.phase.title)
                            .font(CompanionType.caption).foregroundStyle(.dsWarning)
                    }
                }
                if let failure {
                    Text("Not started: \(failure)").font(CompanionType.caption).foregroundStyle(.dsDanger)
                }
            }
            .font(CompanionType.body)
            .scrollContentBackground(.hidden)
            .background(.dsBackground)
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isStarting ? "Starting…" : "Start") { start() }
                        .disabled(!canStart)
                        .accessibilityIdentifier("startTask")
                }
            }
            .onAppear(perform: choose)
            .onChange(of: hostID) { choose() }
        }
    }

    private var host: HostConnection? {
        hostID.flatMap(store.host) ?? store.hosts.first
    }

    private var canStart: Bool {
        guard let host, host.phase.isConnected, agentID != nil, cwd != nil, !isStarting else { return false }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func agents(_ host: HostConnection) -> [(id: String, name: String)] {
        var seen = Set<String>()
        return host.sessions.compactMap { session in
            seen.insert(session.agentID).inserted ? (session.agentID, session.agentName) : nil
        }
    }

    private func projects(_ host: HostConnection) -> [String] {
        var seen = Set<String>()
        return host.sessions.map(\.cwd).filter { seen.insert($0).inserted }
    }

    /// Last-used first: the most recent task's agent and project.
    private func choose() {
        if hostID == nil { hostID = preferredHost ?? store.hosts.first?.id }
        guard let host else { return }
        agentID = host.sessions.first?.agentID
        cwd = host.sessions.first?.cwd
    }

    private func start() {
        guard let host, let agentID, let cwd else { return }
        isStarting = true
        failure = nil
        Task {
            let result = await host.startTask(agentID: agentID, cwd: cwd, prompt: prompt)
            isStarting = false
            switch result {
            case .success: dismiss()
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }
}
