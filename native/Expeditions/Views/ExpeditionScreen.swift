#if EXPEDITIONS_WIP
import NativeExpeditions
import SwiftUI

/// One expedition in the window's detail column: the lead planning, its route to review, or the
/// overview once the crew is under way, with the selected seat's session in the inspector. The app
/// passes the transcript view, so this feature never reaches into the transcript's.
struct ExpeditionScreen<Transcript: View>: View {
    let id: Expedition.ID
    @ViewBuilder let transcript: (SessionModel) -> Transcript

    @Environment(ExpeditionCenter.self) private var center
    @State private var selected: CrewSlot?

    var body: some View {
        if let expedition = center.runner.expedition(id) {
            content(expedition)
                .navigationTitle(expedition.title)
                .navigationSubtitle(expedition.phase.label)
                .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                    if let selected {
                        ExpeditionInspector(expedition: expedition, slot: selected, send: send, transcript: transcript)
                            .inspectorColumnWidth(
                                min: ExpeditionsMetrics.inspectorWidth.min, ideal: ExpeditionsMetrics.inspectorWidth.ideal,
                                max: ExpeditionsMetrics.inspectorWidth.max)
                    }
                }
        } else {
            EmptyStateView("This Expedition Is Gone", systemImage: ExpeditionsMetrics.symbol, message: "It was removed from the list. Its sessions stay with their agents, and its worktree with the project.") {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func content(_ expedition: Expedition) -> some View {
        if expedition.approvedAt == nil, let route = expedition.route, !expedition.isStopped {
            RouteReviewView(expedition: expedition, route: route, send: send, onOpenLead: { selected = .lead })
        } else if expedition.approvedAt == nil, !expedition.isStopped {
            ExpeditionPlanningView(expedition: expedition, send: send, onOpenLead: { selected = .lead })
        } else {
            ExpeditionOverview(expedition: expedition, selected: $selected, send: send)
        }
    }

    private func send(_ event: ExpeditionEvent) {
        center.runner.send(event, to: id)
    }
}

/// While the lead reads the project and drafts the route: who's planning, what it's doing, and the
/// ways out.
private struct ExpeditionPlanningView: View {
    let expedition: Expedition
    let send: (ExpeditionEvent) -> Void
    let onOpenLead: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                ExpeditionHeader(expedition: expedition, send: send)
                ForEach(expedition.attention) { item in
                    ExpeditionAttentionCard(expedition: expedition, item: item, send: send, onOpen: { _ in onOpenLead() })
                }
                if expedition.attention.isEmpty {
                    HStack(alignment: .top, spacing: DS.Space.lg) {
                        DotGridLoader(pattern: .working)
                            .foregroundStyle(.dsAccent)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(expedition.base == nil ? "Making the crew's workspace" : "\(expedition.crew.lead.name) is planning the route")
                                .font(.dsBodyMedium)
                                .foregroundStyle(.dsTextPrimary)
                            Text("It reads the project without changing anything, then proposes legs and assignments for you to review. This usually takes a few minutes.")
                                .font(.dsCaption)
                                .foregroundStyle(.dsTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: DS.Space.lg)
                        if expedition.lead.task != nil {
                            Button("Watch", systemImage: "sidebar.right", action: onOpenLead)
                                .buttonStyle(.ds(.secondary))
                                .help("Show the lead's session beside the expedition")
                        }
                    }
                    .padding(DS.Space.lg)
                    .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
                    .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsSeparator, lineWidth: 1) }
                }
            }
            .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .background(.dsBackground)
    }
}
#endif
