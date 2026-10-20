import ACP
import Dispatch
import Foundation
import NativeHostProtocol
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Serves `LinkControlMethod` on the gateway's control socket. Only the same user can connect (the
/// socket is 0600 in a 0700 folder, and the peer's uid is checked); `verifyPeer` can add the host's
/// code-signature check. A pairing window belongs to the client that opened it and closes with it.
final class LinkControlServer: Sendable {
    private let descriptor: Int32
    private let source: any DispatchSourceRead
    private let clients = Mutex<[UUID: JSONRPCPeer]>([:])

    init(path: String, gateway: LinkGateway, verifyPeer: (@Sendable (Int32) throws -> Void)?) throws {
        let descriptor = try UnixSocket.listen(at: path)
        self.descriptor = descriptor
        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor, queue: DispatchQueue(label: "Native.Link.control"))
        self.source = source
        let logger = HostLogger(category: "LinkControl")
        source.setEventHandler { [weak self] in
            while true {
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else { return }
                var on: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                do {
                    try Self.checkSameUser(client)
                    try verifyPeer?(client)
                } catch {
                    logger.error("Turned a control connection away: \(error.localizedDescription)")
                    _ = close(client)
                    continue
                }
                self?.serve(ByteChannel.socket(client, label: "link-control-\(client)"), gateway: gateway)
            }
        }
        source.setCancelHandler { _ = close(descriptor) }
        source.resume()
    }

    func stop() {
        source.cancel()
        for peer in clients.withLock(\.values) { peer.close() }
    }

    private func serve(_ stream: any ByteStream, gateway: LinkGateway) {
        let id = UUID()
        // The handler needs the peer to answer through, and the peer needs the handler to exist.
        let box = Mutex<JSONRPCPeer?>(nil)
        let peer = JSONRPCPeer(channel: stream, label: "link-control") { [weak self] event in
            switch event {
            case .request(let message):
                guard let requestID = message.id, let peer = box.withLock({ $0 }) else { return }
                await Self.answer(message, requestID: requestID, peer: peer, gateway: gateway, client: id)
            case .notification:
                break
            case .closed:
                box.withLock { $0 = nil }
                _ = self?.clients.withLock { $0.removeValue(forKey: id) }
                await gateway.removeObserver(id)
                // A sheet that went away (the app quit) mustn't leave a window open.
                await gateway.closePairingWindow(ownedBy: id)
            }
        }
        box.withLock { $0 = peer }
        clients.withLock { $0[id] = peer }
        Task {
            await gateway.observe(id: id) { status in
                try? peer.notify(LinkControlMethod.changed, LinkStatusNotification(status: status))
            }
            peer.start()
        }
    }

    private static func answer(
        _ message: JSONRPCPeer.Message, requestID: RequestID, peer: JSONRPCPeer, gateway: LinkGateway, client: UUID
    ) async {
        typealias Method = LinkControlMethod
        do {
            switch message.method {
            case Method.status: break
            case Method.openPairing:
                let params = try? message.params(as: LinkOpenPairingParams.self)
                await gateway.openPairingWindow(preapproving: params?.preapprovedGrants, owner: client)
            case Method.closePairing: await gateway.closePairingWindow()
            case Method.decidePairing:
                let params = try message.params(as: LinkDecisionParams.self)
                await gateway.decidePairing(accept: params.accept, grants: params.grants ?? .standard)
            case Method.revoke: await gateway.revoke(try message.params(as: LinkDeviceParams.self).deviceID)
            case Method.restore: await gateway.restore(try message.params(as: LinkDeviceParams.self).deviceID)
            case Method.rename:
                let params = try message.params(as: LinkDeviceParams.self)
                await gateway.rename(params.deviceID, to: params.name ?? "")
            case Method.setGrants:
                let params = try message.params(as: LinkDeviceParams.self)
                await gateway.setGrants(params.deviceID, to: params.grants ?? .standard)
            case Method.forgetRevoked: await gateway.forgetRevoked()
            case Method.setEnabled:
                await gateway.setEnabled(try message.params(as: LinkEnabledParams.self).isEnabled)
            default:
                throw RPCError(code: -32601, message: "Method not found: \(message.method)")
            }
            try peer.respond(to: requestID, with: await gateway.status)
        } catch let error as RPCError {
            try? peer.respond(to: requestID, error: error)
        } catch {
            try? peer.respond(to: requestID, error: RPCError(code: -32602, message: error.localizedDescription))
        }
    }

    private static func checkSameUser(_ descriptor: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid() else {
            throw CocoaError(.fileReadNoPermission)
        }
    }
}
