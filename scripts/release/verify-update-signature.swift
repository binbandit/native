// Ed25519 verification uses only the public key embedded in the unchanged released app.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    throw CocoaError(.fileReadInvalidFileName)
}
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
let plist = try PropertyListSerialization.propertyList(
    from: Data(contentsOf: URL(fileURLWithPath: arguments[3])), options: [], format: nil
)
guard let values = plist as? [String: Any],
    let encodedKey = values["SUPublicEDKey"] as? String,
    let keyData = Data(base64Encoded: encodedKey),
    let signature = Data(base64Encoded: arguments[2]),
    !archive.isEmpty
else {
    throw CocoaError(.fileReadCorruptFile)
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
guard publicKey.isValidSignature(signature, for: archive) else {
    throw NSError(
        domain: "NativeArchiveSigning", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Embedded public key rejected the archive signature"])
}
var tampered = archive
tampered[tampered.startIndex] ^= 1
guard !publicKey.isValidSignature(signature, for: tampered) else {
    throw NSError(
        domain: "NativeArchiveSigning", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Embedded public key accepted a tampered archive"])
}
print("Embedded SUPublicEDKey accepted the production signature and rejected a tampered archive.")
