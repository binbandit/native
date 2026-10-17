import Foundation

/// Where a host keeps its socket, store and lock. There is one host per user and channel: release
/// builds share the standard location, while each development build gets a channel of its own
/// (derived from its build folder), so builds from different checkouts never fight over one host.
public struct HostLocation: Hashable, Sendable {
    public let directory: URL
    /// Empty for the standard location.
    public let channel: String

    /// The environment variable the launchd plist sets to the host's channel.
    public static let channelVariable = "NATIVE_HOST_CHANNEL"

    public init(directory: URL, channel: String = "") {
        self.directory = directory
        self.channel = channel
    }

    /// `~/Library/Application Support/Native`, or `…/Native/Channels/<channel>` for a named channel.
    public static func standard(channel: String = "") -> HostLocation {
        let support = URL.applicationSupportDirectory.appending(path: "Native", directoryHint: .isDirectory)
        let directory =
            channel.isEmpty ? support : support.appending(path: "Channels/\(channel)", directoryHint: .isDirectory)
        return HostLocation(directory: directory, channel: channel)
    }

    public var socketPath: String {
        directory.appending(path: "host.sock").path(percentEncoded: false)
    }

    public var databaseURL: URL {
        directory.appending(path: "host.sqlite")
    }

    public var lockPath: String {
        directory.appending(path: "host.lock").path(percentEncoded: false)
    }

    /// Creates the directory, readable by the user alone: the socket inside it is the host's door.
    public func prepare() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: directory.path(percentEncoded: false))
    }
}
