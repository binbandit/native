import Darwin
import Foundation
import NativeHost

extension MacHost {
    /// The Mac's name as Sharing sets it ("Brayden's Mac mini").
    public static var machineName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// macOS's version and the Mac's model identifier, for `HostStatus`.
    public static func systemInfo() -> HostSystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        return HostSystemInfo(
            system: "macOS \(version.majorVersion).\(version.minorVersion)\(patch)", model: hardwareModel())
    }

    /// `hw.model`: "Mac16,10" for a Mac mini, "Mac15,3" for a MacBook Pro.
    static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
