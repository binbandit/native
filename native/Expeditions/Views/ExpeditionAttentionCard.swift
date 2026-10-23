import NativeAutomation
import NativeExpeditions
import SwiftUI

/// One thing the expedition needs from the user: what it is, the context to decide, and its one
/// primary action, with the alternatives beside it. The same card for every kind, so "needs you"
/// always looks and works the same.
struct ExpeditionAttentionCard: View {
    let expedition: Expedition
    let item: ExpeditionAttention
    let send: (ExpeditionEvent) -> Void
    /// Opens a seat's session beside the expedition.
    let onOpen: (CrewSlot) -> Void

    @Environment(ExpeditionCenter.self) private var center
    @Environment(\.globalTaskAskShortcut) private var globalShortcut
    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                StatusIndicator(status: status)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(expedition.headline(for: item))
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    if let detail = expedition.detail(for: item) {
                        Text(detail)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let limit {
                        LimitChip(status: limit)
                    }
                }
                Spacer(minLength: DS.Space.md)
            }
            if takesReply, let slot {
                HStack(spacing: DS.Space.sm) {
                    TextField("Reply to \(expedition.agent(of: slot).name)…", text: $reply, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit { sendReply(to: slot) }
                    Button("Reply") { sendReply(to: slot) }
                        .buttonStyle(.ds(.primary))
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            HStack(spacing: DS.Space.sm) {
                actions
                Spacer()
                if let slot, expedition.task(of: slot) != nil {
                    Button("Show Task", systemImage: "sidebar.right") { onOpen(slot) }
                        .buttonStyle(.ds(.ghost))
                }
            }
        }
        .padding(DS.Space.lg)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(
                item.isLimit ? .dsSeparator : .dsAttention.opacity(0.45), lineWidth: 1)
        }
    }

    private var slot: CrewSlot? {
        if case .stopped(let slot, _) = item.kind { return slot }
        return nil
    }

    private var status: TaskStatus {
        switch item.kind {
        case .routeReady, .routeChange: .needsPlanReview
        case .stopped(_, let status): status.expeditionTaskStatus
        case .budgetReached: .paused
        case .baseFailed, .pullRequestFailed: .failed
        }
    }

    private var takesReply: Bool {
        if case .stopped(_, .blocked) = item.kind { return true }
        return false
    }

    /// The Usage feature's own words for a limit, with its reset time.
    private var limit: LimitStatus? {
        guard item.isLimit, let slot else { return nil }
        return center.host?.limitStatus(for: expedition.agent(of: slot).id)
    }

    @ViewBuilder private var actions: some View {
        switch item.kind {
        case .routeReady:
            EmptyView()
        case .routeChange:
            Button("Accept Changes") { send(.approveRouteChange) }
                .buttonStyle(.ds(.primary))
                .help(globalShortcut ? "Apply the lead's revision" : "Apply the lead's revision (⌘Y)")
            Button("Keep the Route") { send(.keepRoute) }
                .buttonStyle(.ds(.secondary))
        case .baseFailed:
            EmptyView()
        case .budgetReached:
            Button("Add the Same Again") { send(.extendBudget) }
                .buttonStyle(.ds(.primary))
            Button("Wrap Up") { send(.wrapUp) }
                .buttonStyle(.ds(.secondary))
                .help("Skip what hasn't started and go straight to the debrief")
            Button("Stop", role: .destructive) { send(.stop) }
                .buttonStyle(.ds(.ghost))
        case .pullRequestFailed:
            Button("Retry") { send(.retryPullRequest) }
                .buttonStyle(.ds(.primary))
            Button("Finish Without It") { send(.finishWithoutPullRequest) }
                .buttonStyle(.ds(.secondary))
        case .stopped(let slot, let status):
            seatActions(slot, status)
        }
    }

    @ViewBuilder private func seatActions(_ slot: CrewSlot, _ status: WorkflowStepStatus) -> some View {
        switch status {
        case .limited:
            Button("Resume Now") { send(.resumeSlot(slot)) }
                .buttonStyle(.ds(.secondary))
        case .interrupted:
            Button("Resume") { send(.resumeSlot(slot)) }
                .buttonStyle(.ds(.primary))
        case .blocked where slot.isCheckpoint:
            Button("Another Round") { send(.anotherRound(slot.leg ?? "")) }
                .buttonStyle(.ds(.secondary))
            Button("Pass the Leg") { send(.accept(slot)) }
                .buttonStyle(.ds(.secondary))
        case .blocked:
            Button("Retry") { send(.retry(slot)) }
                .buttonStyle(.ds(.secondary))
        default:
            Button("Retry") { send(.retry(slot)) }
                .buttonStyle(.ds(.primary))
        }
        if slot != .lead, status != .interrupted {
            if case .assignment = slot {
                Button("Accept as Done") { send(.accept(slot)) }
                    .buttonStyle(.ds(.ghost))
                    .help("Take its latest reply as the report and go on")
            }
            Button("Skip") { send(.skip(slot)) }
                .buttonStyle(.ds(.ghost))
                .help("Go on without it")
        }
    }

    private func sendReply(to slot: CrewSlot) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        send(.message(slot, text: text))
        reply = ""
    }
}

extension CrewSlot {
    var isCheckpoint: Bool {
        if case .checkpoint = self { return true }
        return false
    }

    var leg: String? {
        if case .checkpoint(let leg) = self { return leg }
        return nil
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Attention cards") {
    let expeditions = [ExpeditionPreviewFixtures.reviewing, ExpeditionPreviewFixtures.needsYou]
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(expeditions) { expedition in
                ForEach(expedition.attention) { item in
                    ExpeditionAttentionCard(expedition: expedition, item: item, send: { _ in }, onOpen: { _ in })
                }
            }
        }
        .frame(width: 640)
    }
    .environment(ExpeditionCenter.preview())
}
#endif
