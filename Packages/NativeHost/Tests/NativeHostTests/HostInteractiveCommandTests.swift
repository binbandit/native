import ACP
import Exec
import Foundation
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost
@testable import NativeHostClient

@Suite("Interactive commands on a paired host", .timeLimit(.minutes(1)))
struct HostInteractiveCommandTests {
    @Test func callbackReturnsToOwningHostWithoutJournalContent() async throws {
        let host = try await ExecHost.make()
        let client = try await host.connect(ExecHost.commandingDevice, name: "client")
        let input = CommandInput()
        let result = try await RemoteCommandRunner(client: client).run(
            Command(
                "sh", ["-c", "test -t 0 || exit 7; echo ready; read -r reply; test \"$reply\" = \"$EXPECTED\""],
                in: host.projectPath, environment: ["EXPECTED": "private-callback-code"], timeout: .seconds(5)),
            input: input
        ) { output in
            if String(decoding: output.data, as: UTF8.self).contains("ready") {
                input.send(Data("private-callback-code\n".utf8))
            }
        }
        #expect(result.succeeded)
        #expect(result.output.replacingOccurrences(of: "\r", with: "") == "ready\n")
        #expect(result.errorOutput.isEmpty)
        let journal = try await host.owner.commandsRun()
        #expect(!journal.contains { $0.detail?.contains("private-callback-code") == true })
        await client.stop()
        await host.stop()
    }

    @Test func otherClientsCannotFeedCommandAndDisconnectStopsIt() async throws {
        let host = try await ExecHost.make()
        let client = try await host.connect(ExecHost.commandingDevice, name: "client")
        let other = try await host.connect(ExecHost.commandingDevice, name: "other")
        let denied = try await host.connect(ExecHost.device, name: "denied")
        let execID = UUID()
        let ready = Mutex(false)
        let outputs = await client.execOutputs()
        outputs.add(execID) { _ in ready.withLock { $0 = true } }
        let running = Task {
            let result: ExecRunResult = try await client.call(
                HostProtocol.Method.execRun,
                ExecRunParams(
                    execID: execID, executable: "sh", arguments: ["-c", "echo ready; read -r reply"],
                    directory: host.projectPath, timeout: 5, stream: true, interactive: true))
            return result
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !ready.withLock({ $0 }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ready.withLock { $0 })
        for outsider in [other, denied] {
            await #expect(throws: RPCError.self) {
                let _: EmptyMessage = try await outsider.call(
                    HostProtocol.Method.execInput, ExecInputParams(execID: execID, data: Data("wrong\n".utf8)))
            }
        }
        await client.stop()
        await #expect(throws: (any Error).self) { _ = try await running.value }
        outputs.remove(execID)
        await other.stop()
        await denied.stop()
        await host.stop()
    }
}
