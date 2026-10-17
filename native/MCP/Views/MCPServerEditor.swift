import MCPClient
import SwiftUI

/// Adds or edits a server Native hands agents: what it runs or where it is, its secrets (kept in
/// the Keychain), and which agents and projects get it.
struct MCPServerEditor: View {
    let library: MCPLibrary
    let target: MCPEditorTarget

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MCPServerDraft()
    @State private var didLoad = false
    @State private var attemptedSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text(target == .new ? "Add MCP Server" : "Edit \(draft.name)")
                .settingsText(.title)
                .foregroundStyle(.dsTextPrimary)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    field("Name", note: "Agents show its tools as mcp__\(draft.name.isEmpty ? "name" : draft.name)__tool.") {
                        TextField("Name", text: $draft.name, prompt: Text("linear"))
                            .mcpFieldStyle()
                    }
                    Picker("Type", selection: $draft.kind) {
                        Text("Local command").tag(MCPTransport.Kind.stdio)
                        Text("Remote URL").tag(MCPTransport.Kind.http)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if draft.kind == .stdio {
                        field("Command", note: "Runs with your shell's environment, so npx, uvx and anything on your PATH work.") {
                            TextField("Command", text: $draft.commandLine, prompt: Text("npx -y @example/mcp-server"))
                                .mcpFieldStyle()
                                .font(.dsMono)
                        }
                        MCPSecretList(title: "Environment variables", addTitle: "Add Variable", namePrompt: "API_KEY", pairs: $draft.environment)
                    } else {
                        field("URL", note: "A Streamable HTTP endpoint. Agents that can't use HTTP don't get it.") {
                            TextField("URL", text: $draft.url, prompt: Text("https://mcp.example.com/mcp"))
                                .mcpFieldStyle()
                                .font(.dsMono)
                        }
                        MCPSecretList(title: "Headers", addTitle: "Add Header", namePrompt: "Authorization", pairs: $draft.headers)
                    }
                    MCPChoiceList(title: "Agents", allTitle: "All agents", isAll: $draft.allAgents, chosen: $draft.agents, options: library.agents.map { ($0.id.rawValue, $0.name) })
                    MCPChoiceList(title: "Projects", allTitle: "All projects", isAll: $draft.allProjects, chosen: $draft.projects, options: (library.host?.mcpProjects ?? []).map { (ProjectPath.key($0), $0.lastPathComponent) })
                }
                .padding(.vertical, DS.Space.xs)
            }
            .frame(maxHeight: 520)
            if attemptedSave, let error = validationError {
                Text(error)
                    .settingsText(.body)
                    .foregroundStyle(.dsDanger)
            }
            HStack(spacing: DS.Space.md) {
                Text("Secret values are kept in your Keychain.")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ds(.secondary, size: .large))
                    .keyboardShortcut(.cancelAction)
                Button(target == .new ? "Add Server" : "Save", action: save)
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 600)
        .background(.dsBackground)
        .onAppear(perform: load)
    }

    private func field<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .settingsText(.bodyMedium)
                .foregroundStyle(.dsTextPrimary)
            content()
            Text(note)
                .settingsText(.caption)
                .foregroundStyle(.dsTextTertiary)
        }
    }

    private var id: UUID? {
        if case .edit(let id) = target { id } else { nil }
    }

    private var validationError: String? {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if !ManagedServer.isValidName(name) { return "Give it a name of letters, digits, - and _." }
        if library.availableName(for: name, excluding: id) != name { return "Another server is already called \(name)." }
        switch draft.kind {
        case .stdio:
            guard let words = ShellQuoting.split(draft.commandLine), !words.isEmpty else { return "Enter the command that starts the server; check its quotes." }
        case .http, .sse:
            guard let url = URL(string: draft.url.trimmingCharacters(in: .whitespaces)), ["http", "https"].contains(url.scheme?.lowercased()) else { return "Enter an http or https URL." }
        }
        if draft.environment.contains(where: { $0.name.isEmpty != $0.value.isEmpty }) || draft.headers.contains(where: { $0.name.isEmpty != $0.value.isEmpty }) {
            return "Every variable and header needs a name and a value."
        }
        if !draft.allAgents, draft.agents.isEmpty { return "Choose at least one agent." }
        if !draft.allProjects, draft.projects.isEmpty { return "Choose at least one project." }
        return nil
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let id, let server = library.server(id) {
            draft = MCPServerDraft(server, secrets: library.secrets(for: id))
        }
    }

    private func save() {
        attemptedSave = true
        guard validationError == nil else { return }
        let (server, secrets) = draft.server(id: id ?? UUID(), keeping: id.flatMap(library.server))
        library.save(server, secrets: secrets)
        dismiss()
    }
}

/// The editor's fields, turned into a server and its secrets on save.
struct MCPServerDraft {
    struct Pair: Identifiable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    var name = ""
    var kind = MCPTransport.Kind.stdio
    var commandLine = ""
    var url = ""
    var environment: [Pair] = []
    var headers: [Pair] = []
    var allAgents = true
    var agents: Set<String> = []
    var allProjects = true
    var projects: Set<String> = []

    init() {}

    init(_ server: ManagedServer, secrets: ManagedServerSecrets) {
        name = server.name
        kind = server.transport.kind
        switch server.transport {
        case .stdio(let command, let arguments, let names, _):
            commandLine = ShellQuoting.commandLine([command] + arguments)
            environment = names.map { Pair(name: $0, value: secrets.environment[$0] ?? "") }
        case .http(let url, let names):
            self.url = url.absoluteString
            headers = names.map { Pair(name: $0, value: secrets.headers[$0] ?? "") }
        }
        if case .only(let ids) = server.agents {
            allAgents = false
            agents = Set(ids)
        }
        if case .only(let paths) = server.projects {
            allProjects = false
            projects = Set(paths)
        }
    }

    /// Keeps what the editor doesn't show (working directory, origin, exclusions) from `existing`.
    func server(id: UUID, keeping existing: ManagedServer?) -> (ManagedServer, ManagedServerSecrets) {
        let filled = { (pairs: [Pair]) in Dictionary(pairs.filter { !$0.name.isEmpty }.map { ($0.name.trimmingCharacters(in: .whitespaces), $0.value) }, uniquingKeysWith: { $1 }) }
        let transport: ManagedServer.Transport
        let secrets: ManagedServerSecrets
        if kind == .stdio {
            let words = ShellQuoting.split(commandLine) ?? []
            var directory: String?
            if case .stdio(_, _, _, let existingDirectory)? = existing?.transport { directory = existingDirectory }
            let variables = filled(environment)
            transport = .stdio(command: words.first ?? "", arguments: Array(words.dropFirst()), environmentNames: variables.keys.sorted(), workingDirectory: directory)
            secrets = ManagedServerSecrets(environment: variables)
        } else {
            let values = filled(headers)
            transport = .http(url: URL(string: url.trimmingCharacters(in: .whitespaces)) ?? URL(filePath: "/"), headerNames: values.keys.sorted())
            secrets = ManagedServerSecrets(headers: values)
        }
        var server = existing ?? ManagedServer(id: id, name: name, transport: transport)
        server.name = name.trimmingCharacters(in: .whitespaces)
        server.transport = transport
        server.agents = allAgents ? .all : .only(agents.sorted())
        server.projects = allProjects ? .all : .only(projects.sorted())
        return (server, secrets)
    }
}
