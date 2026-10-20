import ACP
import Foundation
import NativeHostProtocol

/// What the host sees of a paired device: its secure channel, with every request checked against
/// the device's grants first. A refused request is answered here and never reaches the host. The
/// device's `initialize` names it as the host knows it (the name the Mac's user confirmed), so
/// whatever the host records as "from Brayden's iPhone" is true.
final class LinkPolicyStream: ByteStream {
    /// A device sending lines longer than this is cut off: nothing it needs to send comes close.
    static let maximumLine = 8 << 20

    private let channel: SecureChannel
    private let grants: LinkGrants
    private let deviceName: String

    init(channel: SecureChannel, grants: LinkGrants, deviceName: String) {
        self.channel = channel
        self.grants = grants
        self.deviceName = deviceName
    }

    func incoming() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let task = Task { [channel] in
                var buffer = Data()
                for await chunk in channel.incoming() {
                    buffer += chunk
                    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let line = Data(buffer[buffer.startIndex..<newline])
                        buffer = Data(buffer[buffer.index(after: newline)...])
                        if let forwarded = admit(line) {
                            continuation.yield(forwarded + Data([UInt8(ascii: "\n")]))
                        }
                    }
                    if buffer.count > Self.maximumLine {
                        channel.close()
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @discardableResult
    func write(_ data: Data) -> Bool {
        channel.write(data)
    }

    func close() {
        channel.close()
    }

    /// The line to hand the host, or nil when it was refused (and answered) here.
    func admit(_ line: Data) -> Data? {
        guard case .object(var message)? = try? JSONDecoder().decode(JSONValue.self, from: line),
            case .string(let method)? = message["method"]
        else {
            // Responses, and anything unparseable: the host answers malformed input itself.
            return line
        }
        guard LinkMethodPolicy.allows(method, params: message["params"], with: grants) else {
            if let id = message["id"] {
                // A method the device may call, asked for with what only running commands allows,
                // is refused the way the host would.
                refuse(
                    id: id,
                    with: LinkMethodPolicy.allows(method, with: grants)
                        ? HostErrorCode.notAuthorized.rpcError(
                            "This device isn't allowed to run commands on this host, which \(method) as sent would.")
                        : RPCError(code: -32601, message: "\(method) isn't available to this paired device."))
            }
            return nil
        }
        guard method == HostProtocol.Method.initialize,
            case .object(var params)? = message["params"],
            case .object(var clientInfo)? = params["clientInfo"]
        else { return line }
        clientInfo["name"] = .string(deviceName)
        params["clientInfo"] = .object(clientInfo)
        message["params"] = .object(params)
        return (try? JSONEncoder().encode(JSONValue.object(message))) ?? line
    }

    private func refuse(id: JSONValue, with error: RPCError) {
        var fields: [String: JSONValue] = ["code": .number(Double(error.code)), "message": .string(error.message)]
        fields["data"] = error.data
        let response: JSONValue = .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(fields)])
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(UInt8(ascii: "\n"))
        channel.write(data)
    }
}
