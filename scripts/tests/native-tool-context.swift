import Foundation
import MCP
import NativeOrchestration
import ScriptRuntime

@testable import Native

/// Exports production tool declarations without starting agents or reading their configuration.
@main
@MainActor
struct NativeToolContextCapture {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw CaptureFailure.arguments }
        let app = URL(filePath: CommandLine.arguments[1])
        let output = URL(filePath: CommandLine.arguments[2])
        guard let bundle = Bundle(url: app) else { throw CaptureFailure.arguments }
        let runtime = AppTaskRuntime(defaults: PreviewUserDefaults())
        let tools = OrchestrationTools.all(TaskOrchestrator(runtime: AppTaskRuntimeAdapter(base: runtime)))
        let extensions = OrchestrationScriptExtensions()
        let script = OrchestrationScriptTool.make(
            binding: tools, extensions: extensions, runner: try ScriptRunner.embedded(in: bundle))
        let setup = SetupTools.all { _ in throw CaptureFailure.notCalled }
        let skills = SkillTools.all(NativeSkill.bundled(in: bundle), pluginsFolder: URL(filePath: "/fixture/plugins")) {
            skills, _ in skills
        }
        let all = tools + skills + setup + [script].compactMap { $0 }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let captured: JSON = [
            "tools_list": ["jsonrpc": "2.0", "id": 1, "result": ["tools": .array(all.map(\.declaration))]],
            "host_instructions": .string(OrchestrationTools.instructions),
            "app_instructions": .string(
                OrchestrationTools.instructions + (script == nil ? "" : OrchestrationScriptTool.instructions)
                    + SetupTools.instructions),
        ]
        try encoder.encode(captured).write(to: output)
    }

    enum CaptureFailure: Error { case arguments, notCalled }
}
