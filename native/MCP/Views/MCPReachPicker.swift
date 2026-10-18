import MCPClient
import SwiftUI

/// How agents reach a server that's on: loaded into each session, or through Native's run_script,
/// which keeps its tool schemas out of every session's context. For a row's actions menu.
struct MCPReachPicker: View {
    let library: MCPLibrary
    let switchKey: String
    /// The project whose switch it sets; nil for all projects.
    let project: URL?

    var body: some View {
        let mode = library.mode(of: switchKey, in: project)
        Picker(
            "Agents Reach It",
            selection: Binding(
                get: { mode == .scripted ? .scripted : MCPServerSwitches.Mode.on },
                set: { library.setMode($0, of: switchKey, in: project) })
        ) {
            Text("Loaded into Each Session").tag(MCPServerSwitches.Mode.on)
            Text(library.scriptsAvailable ? "Through Native's Scripts" : "Through Native's Scripts (Unavailable)")
                .tag(MCPServerSwitches.Mode.scripted)
        }
        .pickerStyle(.inline)
        // Off has nothing to reach; a build without scripts can still switch back.
        .disabled(mode == .off || (!library.scriptsAvailable && mode != .scripted))
    }
}

extension MCPLibrary {
    /// What running a server through scripts means for it, for its row.
    func scriptNote(for key: MCPServerKey) -> String {
        guard scriptsAvailable else { return "Set to run through scripts, but this build of Native can't run them" }
        guard let tools = reports[key]?.tools, !tools.isEmpty else {
            return "Through Native's run_script · only its read-only tools run in scripts"
        }
        let readOnly = tools.filter { $0.isReadOnly == true }.count
        return "Through Native's run_script · \(readOnly) of \(tools.count) tools run in scripts"
    }
}
