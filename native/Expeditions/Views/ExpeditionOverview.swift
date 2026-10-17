#if EXPEDITIONS_WIP
import NativeAutomation
import NativeExpeditions
import SwiftUI

/// An expedition under way: the header, what needs the user, the debrief once there is one, and
/// the route beside the crew and the logbook (stacked when the window is narrow). Selecting a row
/// opens its session in the inspector.
struct ExpeditionOverview: View {
    let expedition: Expedition
    @Binding var selected: CrewSlot?
    let send: (ExpeditionEvent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                ExpeditionHeader(expedition: expedition, send: send)
                if !expedition.attention.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        SectionHeader("Needs you")
                        ForEach(expedition.attention) { item in
                            ExpeditionAttentionCard(expedition: expedition, item: item, send: send, onOpen: { selected = $0 })
                        }
                    }
                }
                if expedition.debrief != nil || expedition.phase == .debriefing {
                    ExpeditionDebriefCard(expedition: expedition)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DS.Space.xxl) {
                        ExpeditionRouteTimeline(expedition: expedition, selected: $selected)
                            .frame(minWidth: 420)
                        side
                            .frame(width: ExpeditionsMetrics.sideColumn)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        ExpeditionRouteTimeline(expedition: expedition, selected: $selected)
                        side
                    }
                }
            }
            .frame(maxWidth: DS.Size.contentColumn + ExpeditionsMetrics.sideColumn, alignment: .leading)
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .background(.dsBackground)
        // A route change waiting on the user answers the approval keys.
        .background {
            if expedition.pendingRouteChange != nil {
                Button("Accept Route Change") { send(.approveRouteChange) }.keyboardShortcut("y", modifiers: .command).hidden()
                Button("Keep Route") { send(.keepRoute) }.keyboardShortcut(.delete, modifiers: [.command, .shift]).hidden()
            }
        }
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            ExpeditionCrewPanel(expedition: expedition, selected: $selected, send: send)
            ExpeditionLogbook(expedition: expedition, selected: $selected)
        }
    }
}

/// The debrief at the end: the lead's summary and the pull request it became.
private struct ExpeditionDebriefCard: View {
    let expedition: Expedition

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(expedition.phase == .complete ? .dsSuccess : .dsTextSecondary)
                Text(expedition.debrief == nil ? "\(expedition.crew.lead.name) is writing the debrief" : "Debrief")
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Spacer()
                if let pullRequest = expedition.pullRequest {
                    Link(destination: pullRequest.url) {
                        Label(pullRequest.number.map { "Pull Request #\($0)" } ?? "Pull Request", systemImage: "arrow.triangle.pull")
                    }
                    .buttonStyle(.ds(.primary))
                } else if expedition.isOpeningPullRequest {
                    Text("Opening the pull request…")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            if let debrief = expedition.debrief {
                Text(LocalizedStringKey(debrief))
                    .font(.dsBody)
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Copy Debrief", systemImage: "doc.on.doc") { DSPasteboard.copy(debrief) }
                        .buttonStyle(.ds(.ghost))
                    Spacer()
                }
            } else {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsAccent)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            }
        }
        .padding(DS.Space.lg)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsSeparator, lineWidth: 1) }
    }
}
#endif
