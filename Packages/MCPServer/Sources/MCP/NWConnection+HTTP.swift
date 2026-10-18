import Foundation
import Network

extension NWConnection {
    /// `isComplete` once the peer has finished sending or the connection failed.
    func receiveChunk() async -> (data: Data, isComplete: Bool) {
        await withCheckedContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                continuation.resume(returning: (data ?? Data(), isComplete || error != nil))
            }
        }
    }

    func send(_ response: HTTPResponse) async {
        await withCheckedContinuation { continuation in
            send(
                content: response.serialized(), isComplete: true,
                completion: .contentProcessed { _ in continuation.resume() })
        }
    }
}
