import ACP
import Foundation
import NativeHostClient
import Observation

/// A runtime for each agent the plugins provide, kept in step with them as plugins come and go.
/// Runtimes start on their own, so one agent failing leaves the others alone.
@Observable
final class AgentRuntimes {
    private var runtimes: [AgentDefinition.ID: AgentRuntime] = [:]
    @ObservationIgnored private let plugins: PluginRegistry
    /// The host agents run in, once the app connects to one (`HostSessions`); runtimes made after
    /// that run their agents there.
    @ObservationIgnored var host: NativeHostClient?

    init(plugins: PluginRegistry) {
        self.plugins = plugins
    }

    /// In plugin order.
    var all: [AgentRuntime] {
        plugins.agents.compactMap { runtimes[$0.id] }
    }

    subscript(agent: AgentDefinition.ID) -> AgentRuntime? {
        runtimes[agent]
    }

    /// Creates runtimes for agents the plugins added and stops those of agents they took away.
    /// Agents `isIncluded` turns down (ones that aren't installed) get no runtime. Returns the new
    /// runtimes, not yet started, and the ids of the removed ones.
    func sync(
        including isIncluded: (AgentDefinition.ID) -> Bool = { _ in true }
    ) -> (added: [AgentRuntime], removed: [AgentDefinition.ID]) {
        let definitions = plugins.agents.filter { isIncluded($0.id) }
        let current = Set(definitions.map(\.id))
        let removed = runtimes.keys.filter { !current.contains($0) }
        for id in removed {
            runtimes.removeValue(forKey: id)?.stop()
        }
        let added = definitions.filter { runtimes[$0.id] == nil }.map { AgentRuntime(agent: $0, host: host) }
        for runtime in added {
            runtimes[runtime.agent.id] = runtime
        }
        return (added, removed)
    }

    /// Stops an agent and gives it a fresh runtime, with its plugin's current definition.
    func replace(_ agent: AgentDefinition.ID) -> AgentRuntime? {
        runtimes[agent]?.stop()
        guard let definition = plugins.agent(agent) else { return nil }
        let runtime = AgentRuntime(agent: definition, host: host)
        runtimes[agent] = runtime
        return runtime
    }

    func stopAll() {
        runtimes.values.forEach { $0.stop() }
    }
}
