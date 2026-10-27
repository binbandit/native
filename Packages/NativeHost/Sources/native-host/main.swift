import Foundation
import NativeHost
import NativeHostProtocol
import NativeOrchestration

#if os(macOS)
import NativeHostMac
#endif

// A Native host for development, tests and other machines. The app embeds its own helper; this is
// the same host without the app bundle around it.
//
//   native-host [serve] [--home <dir>] [--channel <name>] [--plugins <dir>] [--inherit-environment]
//                       [--exit-with-parent]
//   native-host attach [--home <dir>] [--channel <name>]
//   native-host doctor [--home <dir>] [--channel <name>]
//
// `attach` bridges stdin and stdout to a running host's socket, which is how a client reaches a host
// on another machine: `ssh <machine> native-host attach`.
//
// It builds on macOS and Linux. On Linux there's no `--exit-with-parent` and no updating itself
// (docs/durability.md, "Any machine can be a host").

signal(SIGPIPE, SIG_IGN)

let given = Array(CommandLine.arguments.dropFirst())
let command = given.first.flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "serve"
let arguments = given.first == command ? Array(given.dropFirst()) : given

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("native-host: \(message)\n".utf8))
    exit(status)
}

let channel = option("--channel", in: arguments) ?? ""
let location =
    option("--home", in: arguments).map {
        HostLocation(directory: URL(filePath: $0, directoryHint: .isDirectory), channel: channel)
    }
    ?? HostLocation.standard(channel: channel)

switch command {
case "action":
    NativeActionCLI.run(arguments)

case "serve":
    // A release binary carries its version in an embedded Info.plist (scripts/release/host.sh).
    let bundleInfo = Bundle.main.infoDictionary ?? [:]
    let info = PeerInfo(
        name: "native-host", version: bundleInfo["CFBundleShortVersionString"] as? String ?? "0",
        build: bundleInfo["CFBundleVersion"] as? String ?? "dev")
    let inheritEnvironment = arguments.contains("--inherit-environment")
    let pluginsDirectory = option("--plugins", in: arguments).map { URL(filePath: $0, directoryHint: .isDirectory) }
    #if os(macOS)
    var configuration = MacHost.configuration(
        location: location, info: info, inheritEnvironment: inheritEnvironment, pluginsDirectory: pluginsDirectory)
    #elseif os(Linux)
    var configuration = LinuxHost.configuration(
        location: location, info: info, inheritEnvironment: inheritEnvironment, pluginsDirectory: pluginsDirectory)
    #else
    #error("native-host has a configuration for macOS and Linux only")
    #endif
    // An attached host lives exactly as long as whoever started it, idle or not.
    let isAttached = arguments.contains(HostLocation.exitWithParentArgument)
    #if !os(macOS)
    // Watching the parent's exit takes kqueue; an attached host is the Mac app's anyway.
    if isAttached {
        fail("\(HostLocation.exitWithParentArgument) is only available on macOS")
    }
    #endif
    if isAttached {
        configuration.idleExit = nil
    }
    #if os(macOS)
    // A standalone host just updated gets two launches to come up; one that crashed is rolled back.
    let standalone = configuration.updates.selfUpdater as? StandaloneHostUpdater
    var onTrial = false
    if let standalone {
        do {
            switch try standalone.installer.startupCheck(runningBuild: info.build) {
            case .rolledBack: exit(HostCore.ExitStatus.restart)
            case .trial: onTrial = true
            case .normal: break
            }
        } catch {
            FileHandle.standardError.write(
                Data("native-host: update check failed: \(error.localizedDescription)\n".utf8))
        }
    }
    let confirmTrial = onTrial
    #endif
    let serving = configuration
    Task { @HostActor in
        do {
            #if os(macOS)
            let core = try HostMain.start(serving, verifier: CodeSignatureVerifier())
            if isAttached {
                ParentWatch.stopWithParent(core)
            }
            #else
            // No code signatures to check: as for a Mac development build, the user is the boundary
            // (the socket's folder is theirs alone).
            _ = try HostMain.start(serving, verifier: nil)
            #endif
            FileHandle.standardError.write(Data("native-host: serving at \(location.socketPath)\n".utf8))
        } catch let error as HostMain.Failure {
            if case .alreadyRunning = error { fail(error.localizedDescription, status: 0) }
            fail(error.localizedDescription)
        } catch {
            fail(error.localizedDescription)
        }
        #if os(macOS)
        if confirmTrial, let standalone, await !standalone.confirmWhenServing(at: location) {
            fail("the new build didn't come up within a minute", status: 1)
        }
        #endif
    }
    dispatchMain()

case "attach":
    let socket: Int32
    do {
        socket = try UnixSocket.connect(to: location.socketPath)
    } catch {
        fail("no host at \(location.socketPath): \(error.localizedDescription)")
    }
    let remote = ByteChannel.socket(socket, label: "attach")
    let local = ByteChannel(reading: dup(STDIN_FILENO), writing: dup(STDOUT_FILENO), label: "stdio")
    // Either side closing ends the bridge, once what the other side has to say got through.
    Task {
        for await chunk in remote.incoming() {
            local.write(chunk)
        }
        await local.flushed()
        exit(0)
    }
    Task {
        for await chunk in local.incoming() {
            remote.write(chunk)
        }
        await remote.flushed()
        exit(0)
    }
    dispatchMain()

case "doctor":
    // The doctor's checks (docs/droids.md), from the running host or, with none, of this machine.
    #if os(macOS)
    HostDoctorMac.runCommand(
        location: location,
        version: PeerInfo(
            name: "native-host doctor",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"))
    #else
    fail("doctor is only available on macOS for now")
    #endif

default:
    fail("unknown command \(command); use serve, attach or doctor")
}
