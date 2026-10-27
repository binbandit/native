import Foundation

/// Shared by the bundled host helper and standalone host. Invoking an action never starts a host.
public enum NativeActionCLI {
    public static let endpointVariable = "NATIVE_SESSION_URL"
    public static let sessionsVariable = "NATIVE_ACTION_SESSIONS"

    public static func endpoint(environment: [String: String]) throws -> String {
        if let value = environment[endpointVariable] {
            _ = try NativeActionCommand.endpoint(value)
            return value
        }
        // Codex exports this to its shell tools. Never guess from cwd or another running task.
        guard let directory = environment[sessionsVariable], let thread = environment["CODEX_THREAD_ID"],
            UUID(uuidString: thread) != nil
        else { throw NativeActionCommand.Failure.session }
        let file = URL(filePath: directory).appending(path: thread.lowercased() + ".json")
        guard let data = try? Data(contentsOf: file),
            let credential = try? JSONDecoder().decode(Credential.self, from: data)
        else { throw NativeActionCommand.Failure.session }
        _ = try NativeActionCommand.endpoint(credential.endpoint)
        return credential.endpoint
    }

    public struct Credential: Codable, Sendable {
        public let endpoint: String
        public init(endpoint: String) { self.endpoint = endpoint }
    }

    public static func run(_ arguments: [String]) -> Never {
        if arguments == ["--help"] || arguments == ["help"] {
            FileHandle.standardOutput.write(Data((NativeActionCommand.usage + "\n").utf8))
            exit(0)
        }
        Task {
            do {
                let command = try NativeActionCommand(arguments)
                let endpoint = try endpoint(environment: ProcessInfo.processInfo.environment)
                let output = try await NativeActionClient.call(command, endpoint: endpoint)
                FileHandle.standardOutput.write(Data((output + "\n").utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data(("native: " + error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
        dispatchMain()
    }
}
