import Darwin
import Foundation

/// One isolated instance of Native (`scripts/dev/run-isolated.sh <name>`), found by its name.
///
/// The name is the only way to address a process: the tool never takes a pid, so it can't be pointed
/// at Brayden's own Native, another agent's instance or any other app.
struct Instance {
    let name: String
    let pid: pid_t
    let bundleID: String

    static func resolve(name: String) throws(DriveError) -> Instance {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }) else {
            throw DriveError("name: lowercase letters, digits and dashes only", code: 2)
        }
        // The executable run-isolated.sh launches, matched without the leading /tmp (macOS reports
        // /private/tmp), as its own `pgrep -nf` does.
        let suffix = "/native-dd/\(name)/Build/Products/Debug/Native.app/Contents/MacOS/Native"
        guard let newest = Self.processes().filter({ $0.path.hasSuffix(suffix) }).max(by: { $0.started < $1.started })
        else {
            throw DriveError("\(name) isn't running; start it with scripts/dev/run-isolated.sh \(name)")
        }
        let app = URL(filePath: newest.path).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let id = Bundle(url: app)?.bundleIdentifier, id.hasSuffix(".dev.\(name)") else {
            throw DriveError("\(app.path) isn't \(name)'s isolated build; rebuild it with run-isolated.sh \(name)")
        }
        return Instance(name: name, pid: newest.pid, bundleID: id)
    }

    private struct Process {
        let pid: pid_t
        let path: String
        let started: UInt64
    }

    private static func processes() -> [Process] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        return pids.prefix(max(count, 0)).compactMap { pid in
            guard pid > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
            let path = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            var info = proc_bsdinfo()
            let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            let started = size > 0 ? info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec : 0
            return Process(pid: pid, path: path, started: started)
        }
    }
}

/// A failure to report on stderr, with the exit code to leave with (2 for usage).
struct DriveError: Error {
    let message: String
    let code: Int32

    init(_ message: String, code: Int32 = 1) {
        self.message = message
        self.code = code
    }
}
