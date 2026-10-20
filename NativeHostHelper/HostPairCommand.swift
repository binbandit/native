import Foundation
import NativeHostMac
import NativeHostProtocol
import NativeLink

/// `"Native Host" pair`, run in a shell on this Mac (`ssh mac-mini`) to pair another Mac with its
/// background host when nobody sits at it (`LinkPairCommand`). Add Host on the other Mac runs it
/// over SSH: `<Native.app>/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host pair`.
enum HostPairCommand {
    /// Runs the command and exits with its status.
    static func run(_ arguments: [String], build: PeerInfo) -> Never {
        if arguments.contains("--help") || arguments.contains("-h") {
            write(LinkPairCommand.usage, to: .standardOutput)
            exit(0)
        }
        let options: LinkPairCommand.Options
        do {
            options = try LinkPairCommand.parse(arguments)
        } catch {
            write("Native Host pair: \(error.description)\n\n\(LinkPairCommand.usage)", to: .standardError)
            exit(LinkPairCommand.ExitStatus.usage)
        }
        let command = LinkPairCommand(
            options: options, hostDirectory: location.directory, build: build,
            output: { line, isError in write(line, to: isError ? .standardError : .standardOutput) })
        Task { exit(await command.run()) }
        dispatchMain()
    }

    /// The host of the Native.app around this helper. launchd tells the host its channel; a shell
    /// doesn't, so it comes from the plist the app registers the host with, as the app reads it.
    private static var location: HostLocation {
        let environment = ProcessInfo.processInfo.environment
        guard environment[HostLocation.channelVariable] == nil else {
            return MacHost.location(environment: environment)
        }
        // …/Native.app/Contents/Library/LoginItems/Native Host.app
        let contents = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let plist = contents.appending(path: "Library/LaunchAgents/NativeHost.plist")
        guard let data = try? Data(contentsOf: plist),
            let job = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let bundled = job["EnvironmentVariables"] as? [String: String]
        else { return MacHost.location(environment: [:]) }
        return MacHost.location(environment: bundled)
    }

    /// Unbuffered, so Add Host reading over SSH sees each line as it's written.
    private nonisolated static func write(_ text: String, to handle: FileHandle) {
        handle.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
    }
}
