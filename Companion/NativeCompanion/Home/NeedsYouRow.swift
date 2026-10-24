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
            NavigationLink(value: CompanionDestination.task(TaskRoute(hostID: host.id, sessionID: session.id))) {
                CompanionTaskRow(host: host, session: session)
            }
            .accessibilityIdentifier("task-\(host.name)")
            if let pending = mirror?.state.pendingPermissions.first {
                ApprovalCard(
                    host: host, sessionID: session.id, toolCallID: pending.toolCallID, permission: pending.permission,
                    call: mirror?.state.toolCall(id: pending.toolCallID), isCompact: true)
            } else {
                HStack(spacing: DS.Space.md) {
                    DotGridLoader(pattern: .waiting)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    Text("Loading the request…").font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Needs you - Loading request") {
    let host = CompanionPreviewFixtures.host()
    DSPreviewPair {
        if let session = host.sessions.first {
            NeedsYouRow(host: host, session: session)
                .frame(width: 320)
        }
    }
}
#endif
