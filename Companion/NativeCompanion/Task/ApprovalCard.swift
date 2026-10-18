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
                let summary = CompanionToolSummary(call)
                Text(summary.request)
                    .font(CompanionType.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let detail = summary.detail {
                    ApprovalCommandBlock(text: detail, isCommand: summary.command != nil, isCompact: isCompact)
                }
            }
            if let failure {
                Text("Not sent: \(failure)")
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsDanger)
            }
            VStack(spacing: DS.Space.sm) {
                ForEach(rankedOptions, id: \.option.id) { ranked in
                    optionButton(ranked.option, prominence: ranked.prominence)
                }
            }
        }
        .padding(isCompact ? 0 : DS.Space.lg)
        .background(isCompact ? Color.clear : Color.dsSurfaceRaised, in: .rect(cornerRadius: DS.Radius.panel))
    }

    private func optionButton(_ option: PermissionOption, prominence: ApprovalOptionProminence) -> some View {
        Button {
            answer(option)
        } label: {
            Group {
                if sending == option.optionId {
                    Text("Sending…")
                } else {
                    Text(ApprovalOptionLabel(option.name).attributed)
                }
            }
            .font(prominence == .primary ? CompanionType.bodyMedium : CompanionType.callout)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, DS.Space.sm)
            .frame(maxWidth: .infinity, minHeight: DS.Size.minimumHitTarget)
        }
        .buttonStyle(.ds(prominence.variant, size: .large))
        .disabled(sending != nil)
        .accessibilityLabel(option.name)
        .accessibilityIdentifier("permission-\(option.kind.rawValue)")
    }

    /// One primary answer (the agent's "allow once"), other allows as secondary, rejections as plain
    /// text last: the weight says which answer is the usual one.
    private var rankedOptions: [(option: PermissionOption, prominence: ApprovalOptionProminence)] {
        let primary =
            permission.options.first { $0.kind == .allowOnce } ?? permission.options.first { $0.kind.isAllow }
        return permission.options
            .map { option in
                let prominence: ApprovalOptionProminence =
                    option.id == primary?.id ? .primary : option.kind.isAllow ? .secondary : .tertiary
                return (option, prominence)
            }
            .sorted { $0.prominence < $1.prominence }
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

private enum ApprovalOptionProminence: Int, Comparable {
    case primary, secondary, tertiary

    var variant: DSButtonStyle.Variant {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .tertiary: .ghost
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The command as typed, with a dimmed prompt, or a path without one. The fill is translucent, so
/// the block stands out on the docked card and on a home list row alike.
private struct ApprovalCommandBlock: View {
    let text: String
    let isCommand: Bool
    let isCompact: Bool

    var body: some View {
        Group {
            if isCommand {
                Text("\(Text(verbatim: "$").foregroundStyle(.dsTextSecondary)) \(Text(verbatim: text))")
            } else {
                Text(verbatim: text)
            }
        }
        .font(CompanionType.mono)
        .foregroundStyle(.dsTextPrimary)
        .lineLimit(isCompact ? 2 : 6)
        .textSelection(.enabled)
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.dsFill, in: .rect(cornerRadius: DS.Radius.card))
    }
}

/// An option's name with its `code` spans in the mono face: Codex quotes the command prefix it
/// would stop asking about ("…commands that start with `npm test`").
private struct ApprovalOptionLabel {
    let attributed: AttributedString

    init(_ name: String) {
        var result = AttributedString()
        for (index, part) in name.split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var run = AttributedString(part)
            if index.isMultiple(of: 2) == false { run.font = CompanionType.mono }
            result += run
        }
        attributed = result
    }
}
