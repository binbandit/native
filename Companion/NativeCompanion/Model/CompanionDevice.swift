import NativeHostProtocol
import NativeLink
import UIKit

/// How this phone introduces itself to a host when pairing and connecting.
enum CompanionDevice {
    static var info: LinkDeviceInfo {
        let device = UIDevice.current
        return LinkDeviceInfo(
            name: device.name, model: device.model, system: "\(device.systemName) \(device.systemVersion)")
    }

    static var peerInfo: PeerInfo {
        let bundle = Bundle.main
        return PeerInfo(
            name: UIDevice.current.name,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        )
    }

    /// A random secret for this installation. Hosts only ever see a hash of it with their own key
    /// (`LinkDeviceInfo.installationTag`), so pairing again replaces the old entry on that host
    /// without letting two hosts link this phone.
    static var installationSecret: Data {
        let key = "installationSecret"
        if let data = UserDefaults.standard.data(forKey: key), data.count == 32 { return data }
        var generator = SystemRandomNumberGenerator()
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        UserDefaults.standard.set(data, forKey: key)
        return data
    }

    /// The keychain service paired hosts are kept under.
    static let keychainService = "native.companion.paired-hosts"
}
