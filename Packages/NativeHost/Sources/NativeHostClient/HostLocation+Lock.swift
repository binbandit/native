import Foundation
import NativeHostProtocol

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension HostLocation {
    /// Whether a host process holds this location's lock (`HostMain`): one is running, though it may
    /// be too busy or too early in starting to answer yet. Restarting it would end its agents' work.
    public var isHostRunning: Bool {
        let descriptor = open(lockPath, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return errno == EWOULDBLOCK }
        // Nobody held it. A host starting this instant finds it taken and exits; whoever asked is
        // about to start one anyway.
        _ = flock(descriptor, LOCK_UN)
        return false
    }
}
