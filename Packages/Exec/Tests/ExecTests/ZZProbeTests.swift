#if os(macOS)
import Exec
import Foundation
import Synchronization
import Testing

struct ZZProbeTests {
    @Test func plainTrue() async {
        let stop = Atomic<Bool>(false)
        let busy = Int(ProcessInfo.processInfo.environment["BUSY"] ?? "0") ?? 0
        for _ in 0..<busy {
            Thread.detachNewThread { while !stop.load(ordering: .relaxed) {} }
        }
        defer { stop.store(true, ordering: .relaxed) }
        let runner = LocalCommandRunner()
        let environment = ["PATH": "/usr/bin:/bin"]
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<2000 {
                if index >= 64 { await group.next() }
                group.addTask { _ = try? await runner.run(Command("true", environment: environment)) }
            }
        }
    }
}
#endif
