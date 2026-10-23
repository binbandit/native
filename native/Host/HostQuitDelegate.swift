#if os(macOS)
import AppKit

/// Holds a quit until the background host has stopped, when the quit should stop it: Quit Native
/// and Stop Agents, or background agents turned off during this run (the setting then says agents
/// stop when Native quits). Plain ⌘Q otherwise quits at once and leaves the host working.
final class HostQuitDelegate: NSObject, NSApplicationDelegate {
    weak var host: DurableHost?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // A single SwiftUI Window otherwise quits on close. Closing UI must never stop tasks.
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let client = host?.hostToStopOnQuit else { return .terminateNow }
        // AppKit holds the quit in a modal run loop until the reply. The work runs off the main
        // actor, which may be busy with the very call that asked to quit, and the reply is
        // scheduled in every run loop mode, the modal one included.
        Task.detached {
            await DurableHost.stop(client, within: .seconds(3))
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
            }
        }
        return .terminateLater
    }
}
#endif
