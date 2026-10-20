import ACP
import Foundation
import NativeHostProtocol
import Synchronization

// Signing in, for HostSignInTests, with $FAKE_AGENT_SIGN_IN=1 (without it, the agent offers only
// "token" and reports nothing). Besides "token" (which only records that it was used), it offers "key", an API key taken in `authenticate` and kept in its store (as codex-acp
// does), and, only to clients that advertise URL elicitations, "device": a page and code for the
// user, which it waits on until the test writes `device-approved` to its store or the client
// cancels. It reports who it's signed in as in `_auth/status_update` right after `initialize` and
// after every change: the key's, `$FAKE_AGENT_API_KEY`'s (whose value it writes to `env-key`), the
// device sign-in's account, or nobody. A key starting with "bad" is refused.
extension FakeAgent {
    static let signsIn = ProcessInfo.processInfo.environment["FAKE_AGENT_SIGN_IN"] == "1"

    fileprivate static func signInMethods(for message: JSONRPCPeer.Message) -> [JSONValue] {
        let key = JSONValue.object([
            "id": .string("key"), "name": .string("API key"),
            "_meta": .object(["api-key": .object(["provider": .string("fake")])]),
        ])
        let device = JSONValue.object(["id": .string("device"), "name": .string("Device code")])
        let opensLinks = message.rawParams?["clientCapabilities"]?["elicitation"]?["url"] != nil
        return opensLinks ? [key, device] : [key]
    }

    /// Handles `authenticate` for "key" and "device"; false for any other method.
    func signIn(_ message: JSONRPCPeer.Message, id: RequestID, on peer: JSONRPCPeer) async throws -> Bool {
        guard Self.signsIn else { return false }
        let params = message.rawParams
        switch params?["methodId"]?.stringValue {
        case "key":
            let key = params?["_meta"]?["api-key"]?["apiKey"]?.stringValue ?? ""
            guard !key.isEmpty, !key.hasPrefix("bad") else {
                // Echoing the key, as a careless agent might.
                try peer.respond(to: id, error: RPCError(code: -32000, message: "The API key \(key) was refused."))
                return true
            }
            try Data(key.utf8).write(to: signInFile("key"))
            try reportSignInStatus(on: peer)
            try peer.respond(to: id, with: JSONValue.object([:]))
            return true
        case "device":
            try await signInWithDevice(id: id, on: peer)
            return true
        default:
            return false
        }
    }

    func logOut(id: RequestID, on peer: JSONRPCPeer) throws {
        for name in ["key", "account"] {
            try? FileManager.default.removeItem(at: signInFile(name))
        }
        try reportSignInStatus(on: peer)
        try peer.respond(to: id, with: JSONValue.object([:]))
    }

    func reportSignInStatus(on peer: JSONRPCPeer) throws {
        let fileManager = FileManager.default
        let environmentKey = ProcessInfo.processInfo.environment["FAKE_AGENT_API_KEY"]
        if let environmentKey {
            try Data(environmentKey.utf8).write(to: signInFile("env-key"))
        }
        let (kind, label) =
            if fileManager.fileExists(atPath: signInFile("account").path(percentEncoded: false)) {
                ("account", "Fake Pro")
            } else if fileManager.fileExists(atPath: signInFile("key").path(percentEncoded: false)) {
                ("api_key", "Fake API key")
            } else if environmentKey != nil {
                ("api_key", "Fake API key")
            } else {
                ("none", "Not logged in")
            }
        try peer.notify(
            "_auth/status_update",
            JSONValue.object(["authStatus": .object(["kind": .string(kind), "label": .string(label)])]))
    }

    private func signInWithDevice(id: RequestID, on peer: JSONRPCPeer) async throws {
        let answer = DeviceAnswer()
        Task {
            let response = try? await peer.request(
                "elicitation/create",
                JSONValue.object([
                    "mode": .string("url"), "requestId": Self.json(id), "elicitationId": .string("login-1"),
                    "url": .string("https://example.com/device"),
                    "message": .string("Sign in to Fake and enter this code: ABCD-1234"),
                ]), as: JSONValue.self)
            answer.action.withLock { $0 = response?["action"]?.stringValue ?? "cancel" }
        }
        let approved = signInFile("device-approved").path(percentEncoded: false)
        while true {
            if FileManager.default.fileExists(atPath: approved) {
                try Data().write(to: signInFile("account"))
                try peer.notify("elicitation/complete", JSONValue.object(["elicitationId": .string("login-1")]))
                try reportSignInStatus(on: peer)
                try peer.respond(to: id, with: JSONValue.object([:]))
                return
            }
            if let action = answer.action.withLock({ $0 }), action != "accept" {
                try peer.respond(to: id, error: RPCError(code: -32800, message: "The sign-in was cancelled."))
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func signInFile(_ name: String) -> URL {
        store.appending(path: "signin-\(name)")
    }

    private static func json(_ id: RequestID) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(id))) ?? .null
    }
}

/// How the client answered the device sign-in's link, once it has.
private final class DeviceAnswer: Sendable {
    let action = Mutex<String?>(nil)
}

extension JSONValue {
    /// `initialize`'s result with the fake agent's sign-in methods, logout and status reports
    /// added, when `FakeAgent.signsIn`.
    func addingFakeSignIn(for message: JSONRPCPeer.Message) -> JSONValue {
        guard FakeAgent.signsIn else { return self }
        let methods: [JSONValue] = if case .array(let listed)? = self["authMethods"] { listed } else { [] }
        return merging(
            .object([
                "authMethods": .array(methods + FakeAgent.signInMethods(for: message)),
                "agentCapabilities": .object([
                    "auth": .object(["logout": .object([:])]), "_meta": .object(["authStatus": .object([:])]),
                ]),
            ]))
    }
}
