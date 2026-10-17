#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// `close(2)`, for types whose own `close()` method hides the C function.
func closeDescriptor(_ descriptor: Int32) {
    _ = close(descriptor)
}

#if canImport(os)
import os

/// Logging that works wherever the host runs: the unified log on Apple platforms, stderr elsewhere.
public struct HostLogger: Sendable {
    private let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: "Native", category: category)
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
#else
public struct HostLogger: Sendable {
    private let category: String

    public init(category: String) {
        self.category = category
    }

    public func info(_ message: String) {
        FileHandle.standardError.write(Data("[\(category)] \(message)\n".utf8))
    }

    public func error(_ message: String) {
        FileHandle.standardError.write(Data("[\(category)] error: \(message)\n".utf8))
    }
}
#endif
