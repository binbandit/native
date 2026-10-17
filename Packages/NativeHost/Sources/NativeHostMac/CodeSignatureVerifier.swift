import Darwin
import Foundation
import NativeHost
import Security

/// Lets only this user's processes, and in signed builds only Native's own code, talk to the host.
///
/// The socket's directory is the user's alone, so the uid check mostly guards against mistakes. The
/// signature check is the real boundary: a signed host accepts a peer only when the peer is signed
/// by the same team. Development builds are signed ad hoc and have no team, so there the user is
/// the boundary.
public struct CodeSignatureVerifier: PeerVerifier {
    public enum Rejection: Error, LocalizedError {
        case unreadableCredentials
        case otherUser(uid_t)
        case unsigned(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unreadableCredentials: "The peer's credentials couldn't be read."
            case .otherUser(let uid): "The peer runs as another user (uid \(uid))."
            case .unsigned(let status): "The peer isn't signed by Native's team (\(status))."
            }
        }
    }

    /// The team whose code may connect; nil accepts any process of this user.
    public let teamIdentifier: String?

    public init(teamIdentifier: String? = Self.ownTeamIdentifier()) {
        self.teamIdentifier = teamIdentifier
    }

    public func verify(socket descriptor: Int32) throws {
        var credentials = xucred()
        var length = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERCRED, &credentials, &length) == 0,
            credentials.cr_version == XUCRED_VERSION
        else {
            throw Rejection.unreadableCredentials
        }
        guard credentials.cr_uid == getuid() else { throw Rejection.otherUser(credentials.cr_uid) }
        guard let teamIdentifier else { return }

        var token = audit_token_t()
        length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else {
            throw Rejection.unreadableCredentials
        }
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        var status = SecCodeCopyGuestWithAttributes(
            nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &code)
        guard status == errSecSuccess, let code else { throw Rejection.unsigned(status) }
        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(
            "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\"" as CFString, [],
            &requirement)
        guard status == errSecSuccess, let requirement else { throw Rejection.unsigned(status) }
        status = SecCodeCheckValidity(code, [], requirement)
        guard status == errSecSuccess else { throw Rejection.unsigned(status) }
    }

    /// The team this process is signed by, or nil for ad hoc and unsigned code.
    public static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let information = information as? [String: Any]
        else { return nil }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
