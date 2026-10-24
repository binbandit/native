import ACP
import NativeHostClient
import NativeHostProtocol
import SwiftUI
import Undo

extension SettingsPane.ID {
    static let hosts = Self("hosts")
}

extension SettingsPane {
    /// Settings › Hosts: This Mac and the machines paired with it to run tasks, such as a Mac mini
    /// that keeps working while the laptop sleeps (`docs/durability.md`, "Host identity and many
    /// hosts").
    static let hosts = SettingsPane(
        id: .hosts,
        title: "Hosts",
        systemImage: "macmini",
        group: .agents,
        order: 20,
        keywords: ["host", "remote", "mac mini", "server", "machine", "device", "pair", "ssh", "droid", "sign in"],
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: HostsSettingsPage.addRow, title: "Add Host",
                    description: "Pair a machine that runs tasks while this Mac sleeps.",
                    keywords: ["pair", "mac mini", "remote", "ssh"])
            ]
        },
        content: { HostsSettingsPage() }
    )

    /// Whether Settings lists Hosts. Hidden until paired hosts work end to end: shown only with them
    /// turned on (`RemoteHosts.isEnabled`), or with fixture hosts in a development build.
    static var showsHosts: Bool {
        #if DEBUG
        if HostsFixtureDirectory.scenario != nil { return true }
        #endif
        return RemoteHosts.isEnabled
    }
}

/// Settings ▸ Hosts from the app's hosts, or from fixture hosts with `-NativeHostsFixtures`.
struct HostsSettingsPage: View {
    static let addRow = SettingsRowID("hosts.add")

    static func rowID(_ device: SessionDevice) -> SettingsRowID {
        switch device {
        case .thisMac: SettingsRowID("hosts.thisMac")
        case .remote(let id): SettingsRowID("hosts.\(id.rawValue.uuidString)")
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(DurableHost.self) private var durableHost: DurableHost?
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.openAddHost) private var openAddHost
    @Environment(\.hostLookStore) private var looks
    #if DEBUG
    @State private var fixtures = HostsFixtureDirectory.scenario.map { HostsFixtureDirectory($0) }
    #endif

    var body: some View {
        #if DEBUG
        if HostsFixtureDirectory.scenario == .components {
            HostsComponentsFixturePage()
        } else {
            HostsSettingsContent(directory: directory) { settings.open(.background) }
        }
        #else
        HostsSettingsContent(directory: directory) { settings.open(.background) }
        #endif
    }

    private var directory: any HostsDirectory {
        #if DEBUG
        if let fixtures { return fixtures }
        #endif
        return AppHostsDirectory(
            model: model, durableHost: durableHost, looks: looks ?? .shared,
            openAddHost: openAddHost.map { open in { open() } })
    }
}

/// The page itself: what hosts are for, This Mac and each paired host, and the way to add one.
struct HostsSettingsContent: View {
    let directory: any HostsDirectory
    let openBackgroundSettings: () -> Void

    @State private var renaming: HostDisplay?
    @State private var newName = ""
    @State private var removing: HostDisplay?
    @State private var signingIn: SignInRequest?
    @State private var checking: CheckRequest?
    @State private var undo: UndoToastItem?
    @State private var removedHostUndo: UndoableAction?
    @State private var undoHistory = UndoHistory()
    @Environment(\.undoManager) private var undoManager

    /// The host whose setup is being checked.
    private struct CheckRequest: Identifiable {
        let device: SessionDevice
        let name: String
        let client: NativeHostClient

        var id: SessionDevice { device }
    }

    /// The agent whose sign-in sheet is open, on which host.
    private struct SignInRequest: Identifiable {
        let device: SessionDevice
        let agent: AgentDefinition.ID

        var id: String { "\(device)-\(agent.rawValue)" }
    }

    var body: some View {
        let hosts = directory.hosts
        SettingsPage {
            SettingsHeader(
                title: "Hosts",
                description: Text(
                    "Run tasks on another machine, like a Mac mini at home: start them here, close your laptop, and they keep working there. Each host runs Native's background host and keeps its own checkout of your projects."
                ), plainly: .init(title: "Other Macs", description: "Choose the Macs that run your tasks.")
            ) {
                if hosts.contains(where: { !$0.isThisMac }) {
                    addHostButton(size: .large)
                }
            }
            if let problem = directory.problem {
                ErrorState("Couldn't read paired hosts", suggestion: problem)
            }
            SettingsRowGroup {
                ForEach(hosts) { host in
                    HostSettingsBlock(host: host, actions: actions(for: host))
                }
            }
            if !hosts.contains(where: { !$0.isThisMac }) {
                emptyState
            }
        }
        .alert("Rename Host", isPresented: isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Only this Mac sees this name. Leave it empty to use \(renaming?.machineName ?? renaming?.name ?? "the machine's own name")."
            )
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "this host")?", isPresented: isRemoving, titleVisibility: .visible,
            presenting: removing
        ) { host in
            Button("Remove \(host.name)", role: .destructive) { remove(host) }
            Button("Cancel", role: .cancel) {}
        } message: { host in
            Text(Self.removalMessage(for: host))
        }
        .sheet(item: $signingIn) { request in
            HostAgentSignInSheet(directory: directory, device: request.device, agentID: request.agent)
        }
        .sheet(item: $checking) { request in
            HostDoctorSheet(hostName: request.name, client: request.client)
        }
        .undoToast($undo)
        .onChange(of: undoManager, initial: true) { undoHistory.track(undoManager) }
        .onChange(of: removedHostUndo?.canUndo) {
            if removedHostUndo?.canUndo == false { undo = nil }
        }
        .onChange(of: removedHostUndo.map { undoHistory.willUndo($0) } ?? false) { _, matches in
            undo?.undoesWithCommandZ = matches
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            "No other hosts yet", systemImage: "desktopcomputer.and.macbook",
            message:
                "Add an always-on machine, like a Mac mini, to run tasks there. Start a task from this Mac, close the lid, and it keeps working."
        ) {
            addHostButton(size: .medium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxl)
    }

    private func addHostButton(size: DSButtonStyle.Size) -> some View {
        Button("Add Host…") { directory.addHost() }
            .buttonStyle(.ds(.primary, size: size))
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(!directory.canAddHost)
            .help(directory.canAddHost ? "Pair a machine with this Mac" : "Adding hosts isn't in this build yet")
            .settingsRevealTarget(HostsSettingsPage.addRow)
    }

    // MARK: - Actions

    private func actions(for host: HostDisplay) -> HostSettingsBlock.Actions {
        HostSettingsBlock.Actions(
            rename: {
                newName = host.name
                renaming = host
            },
            setLook: { directory.setLook($0, for: host.device) },
            remove: { removing = host },
            restartHost: host.isThisMac ? { Task { await directory.restartLocalHost() } } : nil,
            setKeepAwake: { mode in
                do {
                    try await directory.setKeepAwake(mode, on: host.device)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            },
            check: checkAction(for: host),
            pairAgain: directory.canAddHost ? { directory.addHost() } : nil,
            openBackgroundSettings: openBackgroundSettings,
            signIn: { agent, method in signIn(agent, with: method, on: host) },
            checkAgain: { agent in
                do {
                    try await directory.checkAgain(agent.id, on: host.device)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        )
    }

    /// Opens the setup check for `host`, while the check is turned on and the host can be reached.
    private func checkAction(for host: HostDisplay) -> (() -> Void)? {
        guard HostDoctorSheet.isAvailable, let client = directory.doctorClient(for: host.device) else { return nil }
        return { checking = CheckRequest(device: host.device, name: host.name, client: client) }
    }

    /// This Mac's agents sign in the way they always do here, with the method picked; a host's get
    /// the sheet that explains signing in on a machine nobody may be sitting at.
    private func signIn(_ agent: HostAgentDisplay, with method: HostSignInMethod?, on host: HostDisplay) {
        guard host.isThisMac, let method else {
            signingIn = SignInRequest(device: host.device, agent: agent.id)
            return
        }
        // The app reports its own failures here (`AppModel.signIn`).
        Task { try? await directory.signIn(agent.id, on: .thisMac, with: method.method, apiKey: nil) }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isRemoving: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private func commitRename() {
        guard let host = renaming, let id = host.device.remoteHostID else { return }
        let oldName = host.name
        directory.rename(id, to: newName)
        let shownName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shownName != oldName else { return }
        removedHostUndo = nil
        undo = UndoToastItem(
            shownName.isEmpty ? "Renamed \(oldName) back to its own name" : "Renamed \(oldName) to \(shownName)"
        ) {
            directory.rename(id, to: oldName)
        }
    }

    private func remove(_ host: HostDisplay) {
        guard let id = host.device.remoteHostID, let restore = directory.remove(id) else { return }
        let action = UndoableAction("Removed \(host.name)", name: "Remove Host", undoManager: undoManager) { _ in
            restore()
        }
        removedHostUndo = action
        undo = UndoToastItem(action.message, undoesWithCommandZ: undoHistory.willUndo(action)) { action.undo() }
    }

    /// What removing does to the host's tasks, in the confirmation.
    static func removalMessage(for host: HostDisplay) -> String {
        let forget = "This Mac forgets its pairing with \(host.name)."
        let sessions = host.sessions
        switch sessions.total {
        case 0:
            return "\(forget) Nothing of yours runs there now. You can add it again anytime."
        default:
            let tasks = sessions.total == 1 ? "its task" : "its \(sessions.total) tasks"
            let working =
                switch sessions.working {
                case 0: ""
                case 1 where sessions.total == 1: ", which is working now,"
                case 1: ", one of them working now,"
                default: ", \(sessions.working) of them working now,"
                }
            return
                "\(forget) \(host.name) keeps running \(tasks)\(working) but they leave this Mac's sidebar. Add \(host.name) again to bring them back."
        }
    }
}

#if DEBUG
#Preview("Hosts page, every state") {
    DSPreviewPair {
        ScrollView {
            HostsSettingsContent(directory: HostsFixtureDirectory(.all)) {}
                .padding(DS.Space.xxl)
        }
        .frame(width: SettingsMetrics.pageMaxWidth, height: 1100)
    }
}

#Preview("Hosts page, no hosts yet") {
    DSPreviewPair {
        HostsSettingsContent(directory: HostsFixtureDirectory(.empty)) {}
            .padding(DS.Space.xxl)
            .frame(width: SettingsMetrics.pageMaxWidth)
    }
}

#Preview("Hosts page, This Mac is unreachable") {
    DSPreviewPair {
        HostsSettingsContent(directory: HostsFixtureDirectory(.localOffline)) {}
            .padding(DS.Space.xxl)
            .frame(width: SettingsMetrics.pageMaxWidth)
    }
}

#Preview("Sign in on a host") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            HostAgentSignInSheet(
                directory: HostsFixtureDirectory(.signin), device: .remote(HostDeviceFixtures.mini),
                agentID: AgentDefinition.ID(rawValue: "codex"))
            HostAgentSignInSheet(
                directory: HostsFixtureDirectory(.signin), device: .remote(HostDeviceFixtures.mini),
                agentID: AgentDefinition.ID(rawValue: "cursor"))
        }
    }
}
#endif
