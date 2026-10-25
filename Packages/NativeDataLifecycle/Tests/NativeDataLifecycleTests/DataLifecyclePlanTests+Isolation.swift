import Foundation
import Testing

@testable import NativeDataLifecycle

/// Planning is a dry run in the strictest sense: it reads no file, writes none, and starts no
/// process, connection or timer.
extension DataLifecyclePlanTests {
    @Test func planningLeavesTheDiskAsItWas() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(
            path: "native-data-lifecycle-\(UUID().uuidString)", directoryHint: .isDirectory)
        let present = scratch.appending(path: "AppSupport", directoryHint: .isDirectory)
        let missing = scratch.appending(path: "HostDir", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sentinel = present.appending(path: "search-index.sqlite")
        try Data("synthetic".utf8).write(to: sentinel)
        let before = try snapshot(scratch)

        let roots = DataApprovedRoots([
            DataRoot(.appSupport): present.path(percentEncoded: false),
            DataRoot(.hostData): missing.path(percentEncoded: false),
        ])
        let host = DataRecord(
            W.alpha, copies: [DataRecordCopy(.primary, at: W.path(.hostData, "host.sqlite"))])
        let planner = W.planner(roots: roots)
        let plan = planner.plan(
            try W.erasure([W.alpha], stores: [.searchIndex, .hostDatabase]),
            reports: [
                .searchIndex: .listed([W.searchRecord(W.alpha, lastActive: W.now)]), .hostDatabase: .listed([host]),
            ],
            clock: W.clock)

        // A path that doesn't exist plans like any other: the planner never checked.
        #expect(plan.outcomes.first { $0.store == .hostDatabase }?.disposition == .planned)
        #expect(plan.operations.count == 4)
        #expect(try snapshot(scratch) == before)
        #expect(!FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))
    }

    @Test func theSourcesCanOnlyComputeAndNeverActOnTheirOwn() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/NativeDataLifecycle")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 5)
        // File, process, network, timer and logging APIs, which nothing in a planner needs.
        let forbidden = [
            "FileManager", "FileHandle", "contentsOf", "write(to", "fopen", "unlink", "remove(", "rename(",
            "Process", "posix_spawn", "NSTask", "URLSession", "URLRequest", "NWConnection", "Socket", "Timer",
            "DispatchSource", "DispatchQueue", "Task {", "Task.detached", "sleep", "Logger", "print(", "UserDefaults",
            "SecItem", "Bundle",
        ]
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            let imports = lines.filter { $0.hasPrefix("import ") }.map { String($0.dropFirst("import ".count)) }
            #expect(Set(imports).isSubset(of: ["Foundation", "NativePolicy"]), "\(file.lastPathComponent)")
            // Comments may explain what adapters must not do; code may not do it.
            let code = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            for token in forbidden {
                #expect(!code.contains(token), "\(file.lastPathComponent) uses \(token)")
            }
        }
    }

    /// Every entry under `folder`: its relative path, size, contents and modification date.
    private func snapshot(_ folder: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return []
        }
        var entries: [String] = []
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: Set(keys))
            let contents = (try? Data(contentsOf: url)).map { $0.base64EncodedString() } ?? "folder"
            entries.append(
                "\(url.lastPathComponent) \(values.fileSize ?? -1) \(contents) "
                    + "\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return entries.sorted()
    }
}
