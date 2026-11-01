import Foundation
import MCP
import NativeOrchestration
import NativeToolEvals

@main
enum ToolEvalCLI {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "list":
            try write(
                JSON.array(
                    ToolUseCases.all.map {
                        ["id": .string($0.id), "kind": .string($0.kind.rawValue), "prompt": .string($0.prompt)]
                    }))
        case "instructions":
            print(OrchestrationTools.instructions)
        case "check-live-policy":
            try EvalLivePolicy.checkInstalledPolicy()
        case "grade" where args.count == 2:
            let trace = try JSONDecoder().decode(EvalTranscript.self, from: Data(contentsOf: URL(filePath: args[1])))
            let test = try testCase(trace.caseID)
            let declarations = EvalSession(test).tools.map(\.declaration)
            let grade = ToolUseGrader.grade(trace, against: test, declarations: declarations)
            try write(JSON(encoding: grade))
            if grade.outcome != .passed { exit(1) }
        case "serve" where args.count == 3:
            try await serve(testCase(args[1]), traceURL: URL(filePath: args[2]))
        default:
            throw CLIError(
                "Usage: native-tool-evals list | instructions | check-live-policy | grade TRACE | serve CASE TRACE")
        }
    }

    private static func testCase(_ id: String) throws -> ToolUseCase {
        guard let test = ToolUseCases.all.first(where: { $0.id == id }) else { throw CLIError("Unknown case: \(id)") }
        return test
    }

    /// MCP stdio transport for the synthetic runtime only. Never connects to Native's running host.
    private static func serve(_ test: ToolUseCase, traceURL: URL) async throws {
        let session = EvalSession(test)
        try await save(session, to: traceURL)
        while let line = readLine() {
            let request = try JSONDecoder().decode(JSON.self, from: Data(line.utf8))
            guard let id = request["id"] else { continue }
            let result: JSON
            switch request["method"]?.stringValue {
            case "initialize":
                result = [
                    "protocolVersion": request["params"]?["protocolVersion"] ?? "2024-11-05",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "native-eval", "version": "1"],
                    "instructions": .string(OrchestrationTools.instructions),
                ]
            case "ping": result = [:]
            case "tools/list": result = ["tools": .array(session.tools.map(\.declaration))]
            case "tools/call":
                guard let name = request["params"]?["name"]?.stringValue else {
                    try write(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Missing tool name"]])
                    continue
                }
                result = await session.call(name, arguments: request["params"]?["arguments"] ?? [:])
                try await save(session, to: traceURL)
            default:
                try write(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
                continue
            }
            try write(["jsonrpc": "2.0", "id": id, "result": result])
        }
    }

    private static func save(_ session: EvalSession, to url: URL) async throws {
        try JSONEncoder().encode(await session.trace()).write(to: url, options: .atomic)
    }

    private static func write(_ value: JSON) throws {
        var data = try JSONEncoder().encode(value)
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    private struct CLIError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
