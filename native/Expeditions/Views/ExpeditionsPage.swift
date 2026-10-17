import NativeAutomation
import NativeExpeditions
import SwiftUI

/// The Expeditions page: every expedition, newest first, and the way to start one. An expedition
/// opens on its own page, with the way back in the toolbar.
struct ExpeditionsPage<Transcript: View>: View {
    @ViewBuilder let transcript: (SessionModel) -> Transcript

    @Environment(ExpeditionCenter.self) private var center

    var body: some View {
        @Bindable var center = center
        NavigationStack(path: $center.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    header
                    if center.runner.expeditions.isEmpty {
                        EmptyStateView(
                            "No Expeditions Yet", systemImage: ExpeditionsMetrics.symbol,
                            message:
                                "Give a crew of agents a large objective. One plans a route you review, others build it in a worktree of their own, another checks each leg, and it ends with a pull request."
                        ) {
                            Button("New Expedition…") { center.isNewExpeditionRequested = true }
                                .buttonStyle(.ds(.primary, size: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.xxxl)
                    } else {
                        list
                    }
                }
                .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
                .padding(DS.Space.xxl)
                .frame(maxWidth: .infinity)
            }
            .background(.dsBackground)
            .navigationTitle("Expeditions")
            .navigationDestination(for: Expedition.ID.self) { id in
                ExpeditionScreen(id: id, transcript: transcript)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Expeditions")
                    .font(.dsTitle2)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    "Large objectives a crew of agents works through for hours, from a route you approve. Any agent can lead, build or review."
                )
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .tracking(DS.Tracking.tight)
            Spacer(minLength: DS.Space.lg)
            Button("New Expedition…", systemImage: "plus") { center.isNewExpeditionRequested = true }
                .buttonStyle(.ds(.primary, size: .medium))
                .help("Start an expedition in the current project (⌥⌘E)")
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Expeditions")
            ForEach(center.runner.expeditions) { expedition in
                ExpeditionRow(expedition: expedition) { center.path = [expedition.id] }
                    .contextMenu {
                        Button("Open") { center.path = [expedition.id] }
                        if expedition.phase.isOver {
                            Button("Remove from List", role: .destructive) { center.runner.remove(expedition.id) }
                        }
                    }
            }
        }
    }
}

/// One expedition in the list: status, title, and where it stands.
private struct ExpeditionRow: View {
    let expedition: Expedition
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: DS.Space.md) {
                StatusIndicator(status: expedition.phase.taskStatus)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(expedition.title)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Text(expedition.metaLine(now: timeline.date))
                            .font(.dsCaption)
                            .monospacedDigit()
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.lg)
                Text(expedition.progressText)
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
                Badge(expedition.phase.label, tone: expedition.phase.tone, style: .mono)
            }
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: DS.Size.rowMinHeight)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the expedition")
    }
}
