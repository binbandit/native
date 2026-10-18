import ACP
import NativeHostProtocol
import SwiftUI

/// The one approval card, sized for a thumb: what exactly is asked, and the agent's own options.
/// The first answer anywhere wins; when the Mac answers first the card simply goes. A failed send
/// keeps the card and says why, never pretending.
struct ApprovalCard: View {
    let host: HostConnection
    let sessionID: HostSessionID
    let toolCallID: String
    let permission: PendingPermission
    let call: ToolCallState?
    var isCompact = false

    @State private var sending: String?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if !isCompact {
                Label("Needs your approval", systemImage: "hand.raised")
                    .font(CompanionType.captionMedium)
                    .foregroundStyle(.dsAttention)
            }
            if let call {
                let presentation = CompanionToolSummary(call)
                Text([presentation.verbs?.base, presentation.subject].compactMap { $0 }.joined(separator: " "))
                    .font(CompanionType.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let command = call.rawInput?["command"]?.stringValue ?? presentation.subtitle {
                    Text(command)
                        .font(CompanionType.mono)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(isCompact ? 2 : 6)
                        .padding(DS.Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
                }
            }
            if let failure {
                Text("Not sent: \(failure)")
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsDanger)
            }
            HStack(spacing: DS.Space.md) {
                ForEach(orderedOptions) { option in
                    Button {
                        answer(option)
                    } label: {
                        Text(sending == option.optionId ? "Sending…" : option.name)
                            .font(CompanionType.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.minimumHitTarget)
                    }
                    .buttonStyle(.ds(option.kind.isAllow ? .primary : .secondary, size: .large))
                    .disabled(sending != nil)
                    .accessibilityIdentifier("permission-\(option.kind.rawValue)")
                }
            }
        }
        .padding(isCompact ? 0 : DS.Space.lg)
        .background(isCompact ? Color.clear : Color.dsSurfaceRaised, in: .rect(cornerRadius: DS.Radius.panel))
    }

    /// Rejecting first, allowing last, so the thumb's natural spot is the agent's "allow once".
    private var orderedOptions: [PermissionOption] {
        let rank: [PermissionOption.Kind: Int] = [.rejectAlways: 0, .rejectOnce: 1, .allowAlways: 2, .allowOnce: 3]
        return permission.options.sorted { (rank[$0.kind] ?? 0) < (rank[$1.kind] ?? 0) }
    }

    private func answer(_ option: PermissionOption) {
        sending = option.optionId
        failure = nil
        Task {
            failure = await host.respond(sessionID, toolCallID: toolCallID, option: option)
            sending = nil
        }
    }
}
