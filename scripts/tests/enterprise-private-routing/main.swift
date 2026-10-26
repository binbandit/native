import Foundation

let route = AgentPrivateRoute(
    identity: AgentRouteIdentity(
        routeID: "qualification-fixture", declarationID: "codex-responses-v1",
        cliVersion: "0.164.0", adapterVersion: "2.2.2"),
    origin: CommandLine.arguments[1], model: "fixture-model",
    authentication: .runtimeEnvironment("NATIVE_PROVIDER_KEY"))
let environment = try CodexConfigOverrides(
    disabledMCPServers: ["fixture-disabled"], disabledSkills: ["/fixture/disabled"]
).environment(for: route)
print(String(decoding: try JSONEncoder().encode(environment), as: UTF8.self))
