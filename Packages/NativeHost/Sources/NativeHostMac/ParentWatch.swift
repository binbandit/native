import Dispatch
import Foundation
import NativeHost
import NativeHostProtocol

#if canImport(Darwin)
import Darwin
#endif

/// For an attached host (one the app started itself, when the user turned Native's background
/// activity off): stops its agents and exits when its parent goes, however the parent ends,
/// `kill -9` included (kqueue's `NOTE_EXIT` on the parent). Asked for with
/// `HostLocation.exitWithParentArgument`.
public enum ParentWatch {
    /// The watch, kept for as long as the process runs.
    @HostActor private static var watch: (any DispatchSourceProcess)?

    /// Starts watching the parent.
    @HostActor
    public static func stopWithParent(_ core: HostCore) {
        let parent = getppid()
        let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global())
        // Dispatch calls this on its own queue, so it mustn't be isolated to the host actor.
        let stop: @Sendable () -> Void = {
            Task { @HostActor in await core.stopAgentsAndExit() }
        }
        source.setEventHandler(handler: stop)
        source.resume()
        watch = source
        // The parent may have gone before the watch began; the process is then launchd's.
        if getppid() != parent || parent <= 1 {
            Task { @HostActor in await core.stopAgentsAndExit() }
        }
    }
}
