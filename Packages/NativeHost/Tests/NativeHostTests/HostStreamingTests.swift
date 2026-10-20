import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

/// Streaming through the host: every chunk arrives, in order, and the host adds little next to
/// talking to the agent directly. The fake agent streams stamped chunks ("<index>@<unix µs>"); each
/// side notes when it has decoded each one into a `SessionUpdate`, ready to fold, as the app would.
/// Folding itself is left out: it's the same work wherever the agent runs.
@Suite("Host streaming", .serialized, .timeLimit(.minutes(1)))
struct HostStreamingTests {
    @Test("A flood of updates arrives complete and in order, and the host keeps up")
    func flood() async throws {
        let chunks = 20_000
        let direct = try await Self.direct("flood \(chunks)")
        let hosted = try await Self.hosted("flood \(chunks)")
        #expect(direct.indices == Array(1...chunks))
        #expect(hosted.indices == Array(1...chunks))
        print(
            """
            \(chunks) chunks as fast as the agent can send them:
              direct to the agent: \(direct.report)
              through the host:    \(hosted.report)
            """)
        // Loose floors, so a busy CI machine doesn't fail them; the numbers above are what to read.
        #expect(hosted.eventsPerSecond > 1_000)
    }

    @Test("At a fast model's pace, the host adds about a millisecond")
    func paced() async throws {
        let chunks = 2_000
        let direct = try await Self.direct("trickle \(chunks)")
        let hosted = try await Self.hosted("trickle \(chunks)")
        #expect(hosted.indices == Array(1...chunks))
        print(
            """
            \(chunks) chunks, one a millisecond:
              direct to the agent: \(direct.report)
              through the host:    \(hosted.report)
            """)
        #expect(hosted.latency(0.5) < .milliseconds(50))
    }

    /// What one side measured.
    struct Measurement: Sendable {
        var indices: [Int] = []
        var latencies: [Duration] = []
        var first: ContinuousClock.Instant?
        var last: ContinuousClock.Instant?
        /// CPU time spent per update by the client and, through a host, by the host process.
        var clientCPU: Duration?
        var hostCPU: Duration?

        mutating func note(_ update: SessionUpdate?) {
            guard case .agentMessageChunk(let chunk)? = update, let text = chunk.content.text,
                let at = text.firstIndex(of: "@"), let index = Int(text[..<at]),
                let stamp = Int64(text[text.index(after: at)...].trimmingCharacters(in: .whitespaces))
            else { return }
            let now = ContinuousClock.now
            first = first ?? now
            last = now
            indices.append(index)
            latencies.append(.microseconds(Int64(Date.now.timeIntervalSince1970 * 1_000_000) - stamp))
        }

        var eventsPerSecond: Double {
            guard let first, let last, last > first else { return 0 }
            return Double(indices.count) / Self.seconds(last - first)
        }

        func latency(_ quantile: Double) -> Duration {
            let sorted = latencies.sorted()
            guard !sorted.isEmpty else { return .zero }
            return sorted[min(sorted.count - 1, Int(Double(sorted.count) * quantile))]
        }

        var report: String {
            let ms = { (duration: Duration) in String(format: "%.2f ms", Self.seconds(duration) * 1_000) }
            let cpu = { (label: String, duration: Duration?) in
                duration.map { String(format: ", %@ CPU %.1f µs/update", label, Self.seconds($0) * 1_000_000) } ?? ""
            }
            return String(format: "%.0f events/s", eventsPerSecond)
                + ", latency p50 \(ms(latency(0.5))), p99 \(ms(latency(0.99))), max \(ms(latency(1)))"
                + cpu("client", clientCPU) + cpu("host", hostCPU)
        }

        private static func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
    }

    /// The app's path before the host: the agent's stdio straight into a peer, decoded per update.
    static func direct(_ prompt: String) async throws -> Measurement {
        let store = FileManager.default.temporaryDirectory.appending(
            path: "native-stream-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store) }
        let command = AgentCommand(
            executable: HostHarness.products.appending(path: "FakeACPAgent").path(percentEncoded: false),
            environment: ["FAKE_AGENT_STORE": store.path(percentEncoded: false), "PATH": "/usr/bin:/bin"])
        let (process, channel, _) = try AgentLaunch.spawn(command) {}
        defer { if process.isRunning { process.terminate() } }
        let measurement = Mutex(Measurement())
        let peer = JSONRPCPeer(channel: channel, label: "direct") { event in
            guard case .notification(let message) = event, message.method == "session/update",
                let notification = try? message.params(as: SessionNotification.self)
            else { return }
            measurement.withLock { $0.note(notification.update) }
        }
        peer.start()
        _ = try await peer.request(
            "initialize", HostInitializeRequest(clientInfo: Implementation(name: "tests", version: "1")),
            as: JSONValue.self)
        let session = try await peer.request(
            "session/new", RawNewSessionRequest(cwd: "/tmp", mcpServers: []), as: RawNewSessionResponse.self)
        let cpu = CPUTime.ofThisProcess()
        _ = try await peer.request(
            "session/prompt", PromptRequest(sessionId: session.sessionId, prompt: [.text(prompt)]),
            as: RawPromptResponse.self)
        let used = CPUTime.ofThisProcess() - cpu
        peer.close()
        return measurement.withLock { measurement in
            measurement.clientCPU = used / max(measurement.indices.count, 1)
            return measurement
        }
    }

    /// Through a real host process, to a client that decodes each event as the app does.
    static func hosted(_ prompt: String) async throws -> Measurement {
        let harness = try HostHarness()
        try harness.start()
        let client = NativeHostClient(
            transport: LocalSocketTransport(location: harness.location),
            clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        let measurement = Mutex(Measurement())
        let ended = Mutex(false)
        await client.addEventHandler { event in
            guard case .sessionEvent(_, let step) = event else { return }
            if case .turnEnded = step.event.payload {
                ended.withLock { $0 = true }
            } else {
                measurement.withLock { $0.note(step.update) }
            }
        }
        await client.start()
        _ = try await client.connected()
        try await client.syncAgents([harness.agentSpec])
        let session = try await client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let host = try #require(await client.hostInfo?.processID)
        let (clientCPU, hostCPU) = (CPUTime.ofThisProcess(), CPUTime.of(host))
        _ = try await client.prompt(PromptParams(sessionID: session.id, text: prompt))
        let deadline = ContinuousClock.now + .seconds(50)
        while !ended.withLock({ $0 }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let (clientUsed, hostUsed) = (CPUTime.ofThisProcess() - clientCPU, CPUTime.of(host) - hostCPU)
        await client.stop()
        return measurement.withLock { measurement in
            let count = max(measurement.indices.count, 1)
            measurement.clientCPU = clientUsed / count
            measurement.hostCPU = hostUsed / count
            return measurement
        }
    }
}

/// CPU time a process has used, user and system.
enum CPUTime {
    static func ofThisProcess() -> Duration {
        var usage = rusage()
        #if canImport(Darwin)
        getrusage(RUSAGE_SELF, &usage)
        #else
        // Glibc declares it as an enum case, and getrusage takes the number.
        getrusage(RUSAGE_SELF.rawValue, &usage)
        #endif
        return .seconds(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + .microseconds(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec)
    }

    static func of(_ pid: Int32) -> Duration {
        #if os(macOS)
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard status == 0 else { return .zero }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanoseconds = (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
        return .nanoseconds(Int64(nanoseconds))
        #else
        // utime and stime, fields 14 and 15 of /proc/<pid>/stat: the 12th and 13th after the command,
        // which ends at the last ")". In clock ticks.
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
            let command = stat.lastIndex(of: ")")
        else { return .zero }
        let fields = stat[stat.index(after: command)...].split(separator: " ")
        guard fields.count > 12, let user = Int64(fields[11]), let system = Int64(fields[12]) else { return .zero }
        return .nanoseconds((user + system) * 1_000_000_000 / max(Int64(sysconf(Int32(_SC_CLK_TCK))), 1))
        #endif
    }
}
