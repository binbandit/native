import NativeHostProtocol
import NativeLink
import UIKit

/// How this phone introduces itself to a host when pairing and connecting.
enum CompanionDevice {
    static var info: LinkDeviceInfo {
        let device = UIDevice.current
        return LinkDeviceInfo(name: device.name, model: device.model, system: "\(device.systemName) \(device.systemVersion)")
    }

    static var peerInfo: PeerInfo {
        let bundle = Bundle.main
        return PeerInfo(
            name: UIDevice.current.name,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        )
    }

    /// The keychain service paired hosts are kept under.
    static let keychainService = "native.companion.paired-hosts"
}
