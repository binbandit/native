import Foundation
import NativeHostProtocol
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs a host: takes the location's lock (one host per location), opens the store, recovers what
/// the previous run left unfinished and serves clients on the socket until told to stop.
public enum HostMain {
    public enum Failure: Error, LocalizedError {
        /// Another host holds the location; this process should exit quietly.
        case alreadyRunning(String)
        case lock(String, errno: Int32)

        public var errorDescription: String? {
            switch self {
            case .alreadyRunning(let path): "Another Native host is already running (\(path) is locked)."
            case .lock(let path, let code): "Couldn't lock \(path): \(String(cString: strerror(code)))"
            }
        }
    }

    /// Starts the host and returns it, serving. The process keeps it alive by not exiting.
    @HostActor
    public static func start(_ configuration: HostCore.Configuration, verifier: (any PeerVerifier)?) throws -> HostCore {
        try configuration.location.prepare()
        try acquireLock(at: configuration.location.lockPath)
        let core = try HostCore(configuration: configuration)
        let server = try SocketServer(path: configuration.location.socketPath, verifier: verifier) { stream in
            Task { @HostActor in core.accept(stream) }
        }
        core.retain(server)
        core.start()
        return core
    }

    /// Holds an exclusive lock on the file for as long as the process lives. The descriptor is left
    /// open on purpose: the kernel drops the lock when the process exits, however it exits.
    private static func acquireLock(at path: String) throws {
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure.lock(path, errno: errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = close(descriptor)
            if code == EWOULDBLOCK { throw Failure.alreadyRunning(path) }
            throw Failure.lock(path, errno: code)
        }
    }
}
