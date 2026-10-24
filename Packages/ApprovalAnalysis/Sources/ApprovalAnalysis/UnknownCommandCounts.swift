import Foundation

/// Bounded, local-only coverage counts. This store has no exporter and never accepts command lines,
/// executable paths, arguments, session identifiers, timestamps, or environment values.
public actor UnknownCommandCounts {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public let program: String
        public let count: Int
        public var id: String { program }
        public init(program: String, count: Int) { self.program = program; self.count = count }
    }

    public enum Failure: Error, LocalizedError {
        case unreadable, invalid, unwritable, unpurgeable
        public var errorDescription: String? {
            switch self {
            case .unreadable: "Command counts could not be read. Check this device's storage permissions."
            case .invalid: "Command counts are damaged. Clear the counts in Settings to start again."
            case .unwritable: "Command counts could not be saved. Check free space and storage permissions."
            case .unpurgeable:
                "Command counts could not be cleared. Check this device's storage permissions and try again."
            }
        }
    }

    private let url: URL
    public init(url: URL) { self.url = url }

    public func record(program: String, enabled: Bool) throws {
        guard enabled, Self.validName(program) else { return }
        var entries = try read()
        if let index = entries.firstIndex(where: { $0.program == program }) {
            entries[index] = Entry(program: program, count: min(entries[index].count + 1, 1_000_000))
        } else {
            guard entries.count < 256 else { return }
            entries.append(Entry(program: program, count: 1))
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw Failure.unwritable }
    }

    public func top(limit: Int = 10) throws -> [Entry] {
        Array(
            try read().sorted { $0.count == $1.count ? $0.program < $1.program : $0.count > $1.count }.prefix(
                max(0, limit)))
    }

    public func purge() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch { throw Failure.unpurgeable }
    }

    private func read() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536 else {
            throw Failure.invalid
        }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw Failure.unreadable }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data), entries.count <= 256,
            Set(entries.map(\.program)).count == entries.count,
            entries.allSatisfy({ Self.validName($0.program) && (1...1_000_000).contains($0.count) })
        else { throw Failure.invalid }
        return entries
    }

    private static func validName(_ value: String) -> Bool {
        value.count <= 64 && !value.hasPrefix("-") && !value.hasPrefix(".")
            && CommandKnowledgeValidation.identifier(value)
    }
}
