import AppKit
import NativeHost
import NativeHostMac
import NativeHostProtocol
import os

// Native's background host: launchd starts it at login and keeps it running, so agents keep working
// while Native's window is closed or the app has quit. It runs as an accessory app (no Dock icon, no
// windows) so it can post notifications and, later, show a menu bar extra. See docs/durability.md.

signal(SIGPIPE, SIG_IGN)

let logger = Logger(subsystem: "Native", category: "Host")
let bundle = Bundle.main
let info = PeerInfo(
    name: "Native Host",
    version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
    build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
)
let location = MacHost.location()
let configuration = MacHost.configuration(location: location, info: info)

Task { @HostActor in
    do {
        _ = try HostMain.start(configuration, verifier: CodeSignatureVerifier())
        logger.info("Serving at \(location.socketPath, privacy: .public)")
    } catch HostMain.Failure.alreadyRunning {
        // Another host owns this location; exiting cleanly keeps launchd from restarting this one.
        logger.info("Another host is running at \(location.socketPath, privacy: .public)")
        exit(0)
    } catch {
        logger.error("Couldn't start: \(error.localizedDescription, privacy: .public)")
        exit(1)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
