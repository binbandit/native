import NativePolicy
import NativeTelemetry

/// Counts sessions started, by agent and the agent's version, for whichever destinations are on.
struct TelemetrySessionPlugin: NativePlugin {
    let manifest = PluginManifest(id: "native.telemetry", name: "Telemetry")

    func handle(_ event: SessionEvent) async {
        // Subagents are counted with the session that started them.
        guard case .sessionStarted(let session) = event, session.parentID == nil else { return }
        let version = await TelemetryCenter.shared.version(of: session.agent)
        Telemetry.record(
            .sessionStarted(
                agent: TelemetryAgent(agentID: session.agent.rawValue),
                agentVersion: version.flatMap(TelemetryVersion.init)))
    }
}
