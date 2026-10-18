import Exec
import Foundation
import Synchronization

/// Checks an MCP server the way an agent would connect to it: launches or reaches it, runs
/// `initialize`, lists its tools and disconnects. It never calls a tool, so probing has no effect
/// beyond the server starting up.
public struct MCPProbe: Sendable {
    public var clientVersion: String
    /// How long the whole probe may take. Local servers started through `npx` can spend a while
    /// downloading the first time.
    public var timeout: Duration
    public var launcher: any StdioLauncher

    public init(clientVersion: String = "0", timeout: Duration = .seconds(60), launcher: any StdioLauncher) {
        self.clientVersion = clientVersion
        self.timeout = timeout
        self.launcher = launcher
    }

    /// - Parameters:
    ///   - environment: What a local server starts with, normally the user's login-shell
    ///     environment; the server's own variables go on top.
    ///   - directory: Where a local server starts, and what a relative working directory in its
    ///     configuration is relative to (the project, or the home folder).
    public func probe(
        _ server: MCPServerConfig, environment: [String: String], directory: String?
    ) async -> MCPProbeReport {
        let startedAt = Date()
        let clock = ContinuousClock()
        let start = clock.now
        let connection = Connection()
        let result = await withTaskGroup(of: Result<(MCPHandshake.Outcome, MCPTransport.Kind), ProbeError>?.self) {
            group in
            group.addTask {
                do throws(ProbeError) {
                    return .success(
                        try await connect(
                            server, environment: environment, directory: directory, connection: connection))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                // Cancelled when the probe finishes first.
                guard (try? await Task.sleep(for: timeout)) != nil else { return nil }
                return .failure(
                    .failure(
                        .initialize,
                        "\(server.name) didn't answer within \(timeout.formatted(.units(allowed: [.seconds], width: .wide))).",
                        exitStatus: nil))
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            // Closing unblocks a probe still waiting on the server, so the group can finish.
            await connection.close()
            return first ?? .failure(.cancelled)
        }
        let duration = clock.now - start
        let stderr = connection.stderr
        switch result {
        case .success(let (outcome, transport)):
            return MCPProbeReport(
                status: .connected, server: outcome.server, tools: outcome.tools, stderr: stderr, startedAt: startedAt,
                duration: duration, transport: transport, toolDefinitionBytes: outcome.toolDefinitionBytes
            )
        case .failure(let error):
            let status: MCPProbeReport.Status =
                switch error {
                case .needsAuth(let challenge): .needsAuth(challenge)
                case .failed(let failure): .failed(failure)
                case .notStreamableHTTP(let status):
                    .failed(
                        MCPProbeFailure(
                            stage: .connect, message: "The server answered HTTP \(status) and doesn't speak SSE either."
                        ))
                case .cancelled: .failed(MCPProbeFailure(stage: .connect, message: "The probe was cancelled."))
                }
            return MCPProbeReport(
                status: status, stderr: stderr, startedAt: startedAt, duration: duration,
                transport: server.transport.kind)
        }
    }

    private func connect(
        _ server: MCPServerConfig, environment: [String: String], directory: String?, connection: Connection
    ) async throws(ProbeError) -> (MCPHandshake.Outcome, MCPTransport.Kind) {
        let handshake = MCPHandshake(clientName: "native", clientTitle: "Native", clientVersion: clientVersion)
        switch server.transport {
        case .stdio(let command, let arguments, let variables, let workingDirectory):
            let transport = try StdioTransport(
                Command(
                    command, arguments, in: Self.directory(workingDirectory, relativeTo: directory),
                    environment: environment.merging(variables) { $1 }),
                launcher: launcher
            )
            connection.set(transport)
            return (try await handshake.run(on: transport), .stdio)
        case .http(let url, let headers):
            let session = connection.session
            let transport = StreamableHTTPTransport(url: url, headers: headers, session: session)
            connection.set(transport)
            do {
                return (try await handshake.run(on: transport), .http)
            } catch .notStreamableHTTP(let status) {
                // Servers from before Streamable HTTP answer a POST with 404 or 405 and stream over GET.
                do throws(ProbeError) {
                    let legacy = try await LegacySSETransport.connect(url: url, headers: headers, session: session)
                    connection.set(legacy)
                    return (try await handshake.run(on: legacy), .sse)
                } catch .failed {
                    throw .notStreamableHTTP(status: status)
                }
            }
        case .sse(let url, let headers):
            let transport = try await LegacySSETransport.connect(
                url: url, headers: headers, session: connection.session)
            connection.set(transport)
            return (try await handshake.run(on: transport), .sse)
        }
    }

    static func directory(_ configured: String?, relativeTo base: String?) -> String? {
        guard let configured, !configured.hasPrefix("/") else { return configured ?? base }
        guard let base else { return configured }
        return URL(filePath: base, directoryHint: .isDirectory).appending(path: configured).standardizedFileURL.path(
            percentEncoded: false)
    }
}

/// The transport a probe is using, so the probe can close it however it ends.
private final class Connection: Sendable {
    let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private let transport = Mutex<(any MCPClientTransport)?>(nil)

    func set(_ transport: any MCPClientTransport) {
        self.transport.withLock { $0 = transport }
    }

    var stderr: String {
        (transport.withLock { $0 } as? StdioTransport)?.stderr ?? ""
    }

    func close() async {
        await transport.withLock { $0 }?.close()
        session.invalidateAndCancel()
    }
}
