import Foundation
import Observation
import SessionTools

/// Every tool features add to the session screen, and where the user put each one. The screen
/// reads only from here (`docs/session-tools.md`).
@Observable
final class SessionToolRegistry {
    static let shared = SessionToolRegistry()

    /// In the order their facts show: Native's own, then enabled plugins'.
    var tools: [SessionToolContribution] { registered + pluginTools }
    /// Enabled plugins' tools (`NativePlugin.sessionTools`), kept in step as plugins come and go.
    private(set) var pluginTools: [SessionToolContribution] = []
    private var registered: [SessionToolContribution] = []
    private(set) var arrangement: SessionToolArrangement {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "sessionTools.arrangement"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        arrangement =
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SessionToolArrangement.self, from: $0) }
            ?? SessionToolArrangement()
    }

    /// Adds a tool, or replaces the one registered with its id.
    func register(_ tool: SessionToolContribution) {
        if let index = registered.firstIndex(where: { $0.id == tool.id }) {
            registered[index] = tool
        } else {
            registered.append(tool)
        }
    }

    func setPluginTools(_ tools: [SessionToolContribution]) {
        pluginTools = tools
    }

    func tool(_ id: SessionToolID) -> SessionToolContribution? {
        tools.first { $0.id == id }
    }

    func place(of id: SessionToolID) -> SessionToolPlace {
        tool(id).map { arrangement.place(of: $0.spec) } ?? .off
    }

    func move(_ id: SessionToolID, to place: SessionToolPlace) {
        guard let tool = tool(id) else { return }
        arrangement.move(tool.spec, to: place)
    }

    /// Where the user put a tool that opens an existing feature (the well's Terminal or Dev)
    /// instead of registering a pane.
    func place(for spec: SessionToolSpec) -> SessionToolPlace {
        arrangement.place(of: spec)
    }

    func setPlace(_ place: SessionToolPlace, for spec: SessionToolSpec) {
        arrangement.move(spec, to: place)
    }

    func resetArrangement() {
        arrangement.reset()
    }

    /// What the screen shows for `session` right now.
    func layout(for session: SessionModel, on screen: SessionToolsScreenModel) -> SessionToolLayout {
        let context = { (tool: SessionToolContribution) in
            SessionToolContext(session: session, screen: screen, tool: tool.id)
        }
        return SessionToolLayout(
            tools: tools.filter { !session.isProjectless || $0.id != .changes }.map(\.spec), arrangement: arrangement,
            withFacts: Set(tools.filter { $0.fact(context($0)) != nil }.map(\.id)),
            withContent: Set(tools.filter { $0.hasContent(context($0)) }.map(\.id)), open: screen.openTools)
    }

    private func save() {
        if arrangement.isDefault {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(arrangement) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
