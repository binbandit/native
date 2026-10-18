import CryptoKit
import Foundation
import Testing

@testable import NativeLink

/// The handshake and transport against the cacophony test vectors (github.com/haskell-cryptography/cacophony,
/// `vectors/cacophony.txt`), the reference most Noise implementations check themselves with.
@Suite struct NoiseVectorTests {
    struct Vector: Decodable {
        struct Message: Decodable {
            let payload: String
            let ciphertext: String
        }

        let protocol_name: String
        let init_prologue: String
        let init_ephemeral: String
        let init_static: String
        let init_psks: [String]?
        let resp_prologue: String
        let resp_ephemeral: String
        let resp_static: String
        let resp_psks: [String]?
        let handshake_hash: String
        let messages: [Message]
    }

    static func vectors() throws -> [Vector] {
        let url = try #require(Bundle.module.url(forResource: "noise-vectors", withExtension: "jsonl", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n").map { try JSONDecoder().decode(Vector.self, from: Data($0.utf8)) }
    }

    @Test(arguments: ["Noise_XX_25519_ChaChaPoly_SHA256", "Noise_XXpsk3_25519_ChaChaPoly_SHA256"])
    func matchesVector(protocolName: String) throws {
        let vector = try #require(try Self.vectors().first { $0.protocol_name == protocolName })
        let pattern: NoisePattern = protocolName.contains("psk3") ? .xxpsk3 : .xx
        var initiator = try NoiseHandshake(
            pattern: pattern, isInitiator: true, prologue: hex(vector.init_prologue),
            localStatic: try .init(rawRepresentation: hex(vector.init_static)),
            preSharedKey: vector.init_psks?.first.map(hex),
            presetEphemeral: try .init(rawRepresentation: hex(vector.init_ephemeral))
        )
        var responder = try NoiseHandshake(
            pattern: pattern, isInitiator: false, prologue: hex(vector.resp_prologue),
            localStatic: try .init(rawRepresentation: hex(vector.resp_static)),
            preSharedKey: vector.resp_psks?.first.map(hex),
            presetEphemeral: try .init(rawRepresentation: hex(vector.resp_ephemeral))
        )

        // Three handshake messages, alternating, then transport messages, alternating.
        for (index, message) in vector.messages.prefix(3).enumerated() {
            let initiatorWrites = index % 2 == 0
            let ciphertext =
                initiatorWrites
                ? try initiator.writeMessage(payload: hex(message.payload))
                : try responder.writeMessage(payload: hex(message.payload))
            #expect(ciphertext == hex(message.ciphertext), "message \(index)")
            let payload =
                initiatorWrites ? try responder.readMessage(ciphertext) : try initiator.readMessage(ciphertext)
            #expect(payload == hex(message.payload))
        }
        #expect(initiator.isComplete && responder.isComplete)
        #expect(initiator.handshakeHash == hex(vector.handshake_hash))
        #expect(responder.handshakeHash == hex(vector.handshake_hash))

        var (initiatorSend, initiatorReceive) = try initiator.split()
        var (responderSend, responderReceive) = try responder.split()
        for (index, message) in vector.messages.dropFirst(3).enumerated() {
            // The responder wrote the last handshake message's reply turn, so transport starts with it.
            let responderWrites = index % 2 == 0
            let ciphertext =
                responderWrites
                ? try responderSend.encrypt(hex(message.payload), associatedData: Data())
                : try initiatorSend.encrypt(hex(message.payload), associatedData: Data())
            #expect(ciphertext == hex(message.ciphertext), "transport message \(index)")
            let payload =
                responderWrites
                ? try initiatorReceive.decrypt(ciphertext, associatedData: Data())
                : try responderReceive.decrypt(ciphertext, associatedData: Data())
            #expect(payload == hex(message.payload))
        }
    }

    @Test func wrongPreSharedKeyFailsTheLastMessage() throws {
        var initiator = try NoiseHandshake(
            pattern: .xxpsk3, isInitiator: true, prologue: Data(), localStatic: .init(), preSharedKey: Data(repeating: 1, count: 32))
        var responder = try NoiseHandshake(
            pattern: .xxpsk3, isInitiator: false, prologue: Data(), localStatic: .init(), preSharedKey: Data(repeating: 2, count: 32))
        _ = try responder.readMessage(try initiator.writeMessage())
        _ = try initiator.readMessage(try responder.writeMessage())
        #expect(throws: NoiseError.decryptFailed) { try responder.readMessage(try initiator.writeMessage()) }
    }

    @Test func differentProloguesNeverAgree() throws {
        var initiator = try NoiseHandshake(pattern: .xx, isInitiator: true, prologue: Data("a".utf8), localStatic: .init())
        var responder = try NoiseHandshake(pattern: .xx, isInitiator: false, prologue: Data("b".utf8), localStatic: .init())
        _ = try responder.readMessage(try initiator.writeMessage())
        #expect(throws: NoiseError.decryptFailed) { try initiator.readMessage(try responder.writeMessage()) }
    }

    private func hex(_ string: String) -> Data {
        var data = Data(capacity: string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            data.append(UInt8(string[index..<next], radix: 16) ?? 0)
            index = next
        }
        return data
    }
}
