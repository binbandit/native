import CoreFoundation
import Foundation

/// Tells one organization policy from another: a fingerprint of every managed policy key's value as
/// delivered. Equal input gives an equal revision on every machine and launch, so audit records and
/// support can say which policy applied. It identifies input; it isn't a security check, and it
/// can't be turned back into values.
public struct PolicyRevision: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public var description: String { value }

    init(_ value: String) {
        self.value = value
    }

    /// Nil when the organization manages nothing and the source read normally.
    static func of(_ source: any PolicySource) -> PolicyRevision? {
        var text = "status=\(source.managedStatus.rawValue)\n"
        var managesAnything = source.managedStatus != .available
        for key in PolicyKey.allCases {
            switch source.managedEntry(forKey: key.rawValue) {
            case .absent: continue
            case .unreadable: text += "\(key.rawValue)!\n"
            case .value(let value): text += "\(key.rawValue)=\(canonical(value))\n"
            }
            managesAnything = true
        }
        guard managesAnything else { return nil }
        // FNV-1a, 64-bit: stable across processes, unlike Hasher.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return PolicyRevision(String(repeating: "0", count: 16 - hex.count) + hex)
    }

    /// One spelling per property-list value, with dictionary keys sorted.
    private static func canonical(_ value: Any) -> String {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            number.boolValue ? "b1" : "b0"
        case let number as NSNumber: "n\(number.stringValue)"
        case let string as String: "s\(string.utf8.count):\(string)"
        case let date as Date: "d\(date.timeIntervalSince1970)"
        case let data as Data: "x\(data.base64EncodedString())"
        case let array as [Any]: "[\(array.map(canonical).joined(separator: ","))]"
        case let dictionary as [String: Any]:
            "{\(dictionary.sorted { $0.key < $1.key }.map { "\(canonical($0.key)):\(canonical($0.value))" }.joined(separator: ","))}"
        default: "?\(type(of: value))"
        }
    }
}
