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
            Text("Loaded into Each Task").tag(MCPServerSwitches.Mode.on)
            Text(library.scriptsAvailable ? "Through Native's Scripts" : "Through Native's Scripts (Unavailable)")
                .tag(MCPServerSwitches.Mode.scripted)
        }
        .pickerStyle(.inline)
        // Off has nothing to reach; a build without scripts can still switch back.
        .disabled(mode == .off || (!library.scriptsAvailable && mode != .scripted))
        if library.scriptApprovals[switchKey]?.isEmpty == false {
            Button("Ask Again Before Scripts Make Changes") { library.forgetScriptApprovals(of: switchKey) }
        }
    }
}

extension MCPLibrary {
    /// What running a server through scripts means for it, for its row: how many of its tools ask
    /// first, and which the user always allows.
    func scriptNote(for key: MCPServerKey, switchKey: String) -> String {
        guard scriptsAvailable else { return "Set to run through scripts, but this build of Native can't run them" }
        var parts = ["Through Native's run_script"]
        if let tools = reports[key]?.tools, !tools.isEmpty {
            let asking = tools.filter { $0.isReadOnly != true }.count
            parts.append(
                asking == 0
                    ? "all \(tools.count) tools are read-only"
                    : "\(asking) of \(tools.count) tools ask first, unless the task runs tools unasked")
        } else {
            parts.append("tools that can make changes ask first, unless the task runs tools unasked")
        }
        if let allowed = scriptApprovals[switchKey], !allowed.isEmpty {
            parts.append("always allowed: " + allowed.sorted().joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}
