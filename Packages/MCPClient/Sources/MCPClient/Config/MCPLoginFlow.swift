import Exec
import Foundation
import Observation
import Synchronization

/// One explicitly requested MCP sign-in. Network access and credential storage stay in the agent's
/// CLI; the caller checks its MCP policy before starting. No raw command output is retained here.
@MainActor @Observable
public final class MCPLoginFlow {
    public enum Phase: Equatable, Sendable {
        case ready, starting, waiting, succeeded, cancelled
        case failed(String)
    }

    public private(set) var phase: Phase = .ready
    public private(set) var authorization: MCPAuthorizationLink?
    public private(set) var inputProblem: String?
    @ObservationIgnored private var input: CommandInput?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    public init() {}

    public var isRunning: Bool { phase == .starting || phase == .waiting }

    public func start(
        _ command: Command, runner: any CommandRunner, onCompletion: @escaping @MainActor () async -> Void = {}
    ) {
        guard !isRunning else { return }
        generation = UUID()
        let generation = generation
        let input = CommandInput()
        self.input = input
        phase = .starting
        authorization = nil
        inputProblem = nil
        let parser = Mutex(MCPLoginOutput())
        task = Task { [weak self] in
            let receiver = self
            do {
                let result = try await runner.run(command, input: input) { [weak receiver] output in
                    let links = parser.withLock { $0.receive(output.data) }
                    for link in links {
                        Task { @MainActor [weak receiver] in
                            guard let self = receiver, self.generation == generation, self.isRunning else { return }
                            self.authorization = link
                            self.phase = .waiting
                        }
                    }
                }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.phase =
                    result.succeeded
                    ? .succeeded
                    : .failed(
                        "Sign-in didn't finish. Try again and complete the browser step. If no page opens, update the agent's CLI."
                    )
                self.authorization = nil
                self.input = nil
                await onCompletion()
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.phase = .failed(
                    error is CommandError
                        ? error.localizedDescription
                        : "The host couldn't finish signing in. Check its connection and try again.")
                self.authorization = nil
                self.input = nil
            }
        }
    }

    @discardableResult
    public func submitCallback(_ text: String) -> Bool {
        guard phase == .waiting, let callback = authorization?.callback(text) else {
            inputProblem = "Paste the full redirect address from the browser page opened by this sign-in."
            return false
        }
        guard input?.send(Data((callback.absoluteString + "\r").utf8)) == true else {
            inputProblem = "The host isn't accepting input. Cancel and try signing in again."
            return false
        }
        inputProblem = nil
        return true
    }

    public func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        input?.finish()
        input = nil
        authorization = nil
        inputProblem = nil
        if isRunning { phase = .cancelled }
    }
}
