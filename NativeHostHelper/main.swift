import AppKit
import NativeHost
import NativeHostMac
import NativeHostProtocol
import NativeLink
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
var configuration = MacHost.configuration(location: location, info: info)
// Started by the app itself (background activity is off): it lives exactly as long as the app.
let isAttached = CommandLine.arguments.contains(HostLocation.exitWithParentArgument)
if isAttached {
    configuration.idleExit = nil
}
let serving = configuration

Task { @HostActor in
    do {
        let core = try HostMain.start(serving, verifier: CodeSignatureVerifier())
        if isAttached {
            ParentWatch.stopWithParent(core)
        }
        logger.info("Serving at \(location.socketPath, privacy: .public)")
        // Paired devices (docs/companion.md): nothing listens on the network until one is paired.
        let gateway = try LinkGateway(
            configuration: .init(
                directory: LinkGateway.Configuration.directory(inHostDirectory: location.directory),
                hostID: core.hostID, machineName: serving.machineName,
                includesLoopback: location.isDevelopment),
            accept: { stream, grants in
                Task { @HostActor in
                    core.accept(
                        stream,
                        grants: ClientGrants(
                            managePlugins: grants.managePlugins, manageHost: grants.manageHost, isLocal: false))
                }
            })
        try await gateway.start(verifyPeer: { try CodeSignatureVerifier().verify(socket: $0) })
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
