import Foundation
import NativeHostProtocol
import Testing

@Suite("Host locations")
struct HostLocationTests {
    @Test("The standard host uses the user's application support directory")
    func standardLocation() throws {
        let base = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let location = HostLocation.standard()
        #expect(location.directory == base.appending(path: "Native", directoryHint: .isDirectory))
        #expect(location.channel.isEmpty)
        #expect(!location.isDevelopment)
    }

    @Test("Named channels keep their socket, store and lock separate", arguments: ["nightly", "dev-pr28"])
    func channelLocation(channel: String) {
        let standard = HostLocation.standard()
        let location = HostLocation.standard(channel: channel, isDevelopment: true)
        let directory = standard.directory.appending(path: "Channels/\(channel)", directoryHint: .isDirectory)
        #expect(location.directory == directory)
        #expect(location.channel == channel)
        #expect(location.isDevelopment)
        #expect(location.socketPath == directory.appending(path: "host.sock").path(percentEncoded: false))
        #expect(location.databaseURL == directory.appending(path: "host.sqlite"))
        #expect(location.lockPath == directory.appending(path: "host.lock").path(percentEncoded: false))
        #expect(location.socketPath != standard.socketPath)
        #expect(location.databaseURL != standard.databaseURL)
        #expect(location.lockPath != standard.lockPath)
    }
}
