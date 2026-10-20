import Dispatch
import Foundation
import NativeHost
import NativeHostProtocol

#if canImport(Darwin)
import Darwin
#endif

/// For an attached host (one the app started itself, when the user turned Native's background
/// activity off): it lives exactly as long as the app. When the app goes, however it ends (`kill -9`
/// included, through kqueue's `NOTE_EXIT` on the parent), or when the host itself is asked to
/// terminate (SIGTERM from a logout or a script, SIGINT, SIGHUP), it stops the way Quit Native and
/// Stop Agents does: running turns end as stopped by the user, agents stop, the clean-shutdown mark
/// is written and it exits 0. Quitting the app is how an attached host's agents are meant to stop, so
/// the next host never reads it as a crash and resumes nothing. Asked for with
/// `HostLocation.exitWithParentArgument`.
public enum ParentWatch {
    /// The parent and signal watches, kept for as long as the process runs.
    @HostActor private static var sources: [any DispatchSourceProtocol] = []
    @HostActor private static var isStopping = false

    /// The signals that end an attached host the same way as its parent going.
    static let stopSignals = [SIGTERM, SIGINT, SIGHUP]

    /// Starts watching the parent and the termination signals.
    @HostActor
    public static func stopWithParent(_ core: HostCore) {
        // Dispatch calls these on its own queue, so they mustn't be isolated to the host actor.
        let stop: @Sendable () -> Void = {
            Task { @HostActor in await stopOnce(core) }
        }
        let parent = getppid()
        let parentExit = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global())
        parentExit.setEventHandler(handler: stop)
        parentExit.resume()
        sources.append(parentExit)
        for number in stopSignals {
            // The default action would end the process at once, mid-turn.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler(handler: stop)
            source.resume()
            sources.append(source)
        }
        // The parent may have gone before the watch began; the process is then launchd's.
        if getppid() != parent || parent <= 1 {
            stop()
        }
    }

    /// The parent's exit and a signal can arrive together; the host stops once.
    @HostActor
    private static func stopOnce(_ core: HostCore) async {
        guard !isStopping else { return }
        isStopping = true
        await core.stopAgentsAndExit()
    }
}
