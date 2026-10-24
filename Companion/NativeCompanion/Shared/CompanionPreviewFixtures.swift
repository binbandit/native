#if DEBUG
import ACP
import NativeHostProtocol
import NativeLink
import SwiftUI

enum CompanionPreviewFixtures {
    static func host() -> HostConnection {
        let identity = LinkIdentity()
        let pairing: PairedHost
        do {
            let data = try JSONEncoder().encode(PreviewPairing(identity: identity))
            pairing = try JSONDecoder().decode(PairedHost.self, from: data)
        } catch {
            preconditionFailure("Invalid companion preview pairing: \(error)")
        }
        let sessions = ["Polish the task sidebar", "Add keyboard navigation", "Review the latest changes"].map {
            title in
            HostSessionSummary(
                id: HostSessionID(), agentID: "codex", agentName: "Codex", agentSessionID: nil,
                cwd: "native", title: title, phase: .idle, lastStopReason: "end_turn")
        }
        var mirror = SessionMirror()
        for step in 1...12 {
            mirror.state.appendUserMessage("Review pass \(step): keep the task list clear at every width.")
            mirror.state.apply(
                .agentMessageChunk(
                    ContentChunk(
                        content: .text(
                            """
                            The sidebar keeps related tasks together. The conversation uses the remaining space, \
                            with the message field ready for your next instruction.

                            **Checked:** task titles, connection status, and the conversation's reading position.
                            """))))
            mirror.state.endTurn(.endTurn)
        }
        return HostConnection(previewHost: pairing, sessions: sessions, mirror: mirror)
    }

    /// Uses the saved-pairing format without opening a real pairing session.
    private struct PreviewPairing: Encodable {
        let hostID = HostID()
        let machineName = "Studio Mac"
        let deviceID = UUID()
        let grants = LinkGrants()
        let addresses: [LinkAddress] = []
        let pairedAt = Date.now
        let hostKey: LinkPublicKey
        let deviceKey: Data

        init(identity: LinkIdentity) {
            hostKey = identity.publicKey
            deviceKey = identity.rawRepresentation
        }
    }
}

#endif
