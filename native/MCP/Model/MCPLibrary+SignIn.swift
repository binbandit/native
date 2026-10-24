import Exec
import Foundation
import MCPClient
import NativePolicy

extension MCPLibrary {
    func openSignInBrowser(_ command: AgentCLICommand, flow: MCPLoginFlow) -> String? {
        guard organizationPolicy.allows(name: command.serverName) else {
            flow.cancel()
            return "Your policy settings don't allow signing in to this MCP server."
        }
        if let authorization = flow.authorization { PlatformURLOpener.open(authorization.url) }
        return nil
    }

    /// Sign-in is initiated here so policy, host selection and configuration refresh do not depend
    /// on which Settings or task view presented it. The browser always belongs to this client.
    func startSignIn(_ command: AgentCLICommand, flow: MCPLoginFlow, task: SessionModel? = nil) async -> String? {
        guard command.action == .signIn else { return "This command isn't a sign-in." }
        guard organizationPolicy.allows(name: command.serverName) else {
            return "Your policy settings don't allow signing in to this MCP server."
        }
        do {
            let runner: any CommandRunner
            let environment: [String: String]
            var invocation: Command
            if let task {
                runner = try task.commandRunner()
                environment = [:]
                invocation = command.command(environment: environment)
                invocation.directory = task.cwd.path(percentEncoded: false)
            } else {
                runner = self.runner
                environment = await host?.mcpEnvironment() ?? [:]
                invocation = command.command(environment: environment)
            }
            guard !Task.isCancelled else { return nil }
            flow.start(invocation, runner: runner) { [weak self] in
                await self?.readConfigurations()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
