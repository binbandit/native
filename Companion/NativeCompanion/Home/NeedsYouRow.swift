import ACP
import NativeHostProtocol
import SwiftUI

/// A task waiting on the person, answerable without opening it: what it asks and its options.
struct NeedsYouRow: View {
    let host: HostConnection
    let session: HostSessionSummary

    var body: some View {
        let mirror = host.mirrors[session.id]
        VStack(alignment: .leading, spacing: DS.Space.md) {
            NavigationLink(value: TaskRoute(hostID: host.id, sessionID: session.id)) {
                CompanionTaskRow(host: host, session: session)
            }
            if let pending = mirror?.state.pendingPermissions.first {
                ApprovalCard(
                    host: host, sessionID: session.id, toolCallID: pending.toolCallID, permission: pending.permission,
                    call: mirror?.state.toolCall(id: pending.toolCallID), isCompact: true)
            } else {
                HStack(spacing: DS.Space.md) {
                    DotGridLoader(pattern: .waiting)
                    Text("Loading the request…").font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
                }
            }
        }
    }
}
