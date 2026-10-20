#if os(macOS)
import AppKit

/// Holds a quit until the background host has stopped, when the quit should stop it: Quit Native
/// and Stop Agents, or background agents turned off during this run (the setting then says agents
/// stop when Native quits). Plain ⌘Q otherwise quits at once and leaves the host working.
final class HostQuitDelegate: NSObject, NSApplicationDelegate {
    weak var host: DurableHost?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let host, host.quitStopsHost else { return .terminateNow }
        Task {
            await host.stopHostForQuit()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
