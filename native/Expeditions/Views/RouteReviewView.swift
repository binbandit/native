#if EXPEDITIONS_WIP
import NativeAutomation
import NativeExpeditions
import SwiftUI

/// The lead's route as a document to review: its approach, its questions to answer, its
/// assumptions, and every leg and assignment, all editable in place. Approving is the one-way door:
/// from then on the crew works to the route.
struct RouteReviewView: View {
    let expedition: Expedition
    let route: Route
    let send: (ExpeditionEvent) -> Void
    let onOpenLead: () -> Void

    @State private var draft: Route
    @State private var removed: Set<String> = []
    @State private var feedback = ""

    init(expedition: Expedition, route: Route, send: @escaping (ExpeditionEvent) -> Void, onOpenLead: @escaping () -> Void) {
        self.expedition = expedition
        self.route = route
        self.send = send
        self.onOpenLead = onOpenLead
        _draft = State(initialValue: route)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    ExpeditionHeader(expedition: expedition, send: send)
                    if isRevising {
                        NoticeBanner(tone: .info, title: "\(expedition.crew.lead.name) is revising the route", detail: "Your edits below are kept until the revision arrives.")
                    }
                    ForEach(expedition.attention.filter { $0.kind != .routeReady }) { item in
                        ExpeditionAttentionCard(expedition: expedition, item: item, send: send, onOpen: { _ in onOpenLead() })
                    }
                    intro
                    if !draft.summary.isEmpty {
                        section("Approach") {
                            Text(draft.summary)
                                .font(.dsCallout)
                                .foregroundStyle(.dsTextPrimary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !draft.questions.isEmpty {
                        section("Questions from \(expedition.crew.lead.name)") {
                            ForEach(draft.questions.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: DS.Space.xs) {
                                    Text(draft.questions[index].text)
                                        .font(.dsBody)
                                        .foregroundStyle(.dsTextPrimary)
                                    TextField("Your answer, shared with every builder", text: Binding(
                                        get: { draft.questions[index].answer ?? "" },
                                        set: { draft.questions[index].answer = $0 }
                                    ), axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.dsBody)
                                }
                            }
                        }
                    }
                    if !draft.assumptions.isEmpty {
                        section("Assumptions") {
                            ForEach(draft.assumptions, id: \.self) { assumption in
                                Label(assumption, systemImage: "circle.fill")
                                    .labelStyle(BulletLabelStyle())
                            }
                        }
                    }
                    ForEach(draft.legs.indices, id: \.self) { legIndex in
                        legSection(legIndex)
                    }
                }
                .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
                .padding(DS.Space.xxl)
                .frame(maxWidth: .infinity)
            }
            SeparatorLine()
            footer
        }
        .background(.dsBackground)
        .onChange(of: route) { _, revised in
            draft = revised
            removed = []
        }
        // The route answers the approval keys, like every other approval card.
        .background {
            Button("Approve Route", action: approve).keyboardShortcut("y", modifiers: .command).hidden().disabled(isRevising)
            Button("Discard Route") { send(.discard) }.keyboardShortcut(.delete, modifiers: [.command, .shift]).hidden()
        }
    }

    private var isRevising: Bool {
        expedition.lead.status.isActive
    }

    private var changed: Set<String> {
        expedition.previousRoutes.last.map(route.changedAssignments(since:)) ?? []
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(expedition.previousRoutes.isEmpty ? "Review the route" : "Review the revised route")
                .font(.dsTitle3)
                .foregroundStyle(.dsTextPrimary)
            Text("Edit anything, answer the lead's questions, or remove what you don't want. Approving sets the crew out; from then on they work to this route, and changes to it come back to you.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tracking(DS.Tracking.tight)
    }

    private func legSection(_ legIndex: Int) -> some View {
        let leg = draft.legs[legIndex]
        return section("Leg \(legIndex + 1) · \(leg.title)") {
            Text(leg.outcome)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
            ForEach(leg.assignments.indices, id: \.self) { index in
                RouteAssignmentEditor(
                    assignment: $draft.legs[legIndex].assignments[index],
                    agents: agents,
                    isRemoved: removed.contains(leg.assignments[index].id),
                    isChanged: changed.contains(leg.assignments[index].id),
                    toggleRemoved: { toggleRemoved(leg.assignments[index].id) }
                )
            }
            Label("Checkpoint: \(expedition.crew.reviewer.name) checks the leg against every “done when”.", systemImage: "checkmark.seal")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            TextField("Ask \(expedition.crew.lead.name) for changes…", text: $feedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(requestChanges)
            Button("Ask for Changes", action: requestChanges)
                .buttonStyle(.ds(.secondary, size: .medium))
                .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRevising)
            Button("Discard", role: .destructive) { send(.discard) }
                .buttonStyle(.ds(.ghost, size: .medium))
                .help("Stop the expedition without starting the crew (⇧⌘⌫)")
            Button("Approve and Set Out", action: approve)
                .buttonStyle(.ds(.primary, size: .medium))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isRevising || approvedRoute.assignments.isEmpty)
                .help("Start the crew on this route (⌘Return or ⌘Y)")
        }
        .padding(.horizontal, DS.Space.xxl)
        .padding(.vertical, DS.Space.lg)
        .frame(maxWidth: DS.Size.contentColumn + 2 * DS.Space.xxl)
        .frame(maxWidth: .infinity)
    }

    private var agents: [WorkflowAgent] {
        var agents = expedition.crew.agents
        for builder in expedition.crew.builders where !agents.contains(builder) {
            agents.append(builder)
        }
        return agents
    }

    /// The draft without what the user removed; work that came after a removed assignment no longer
    /// waits for it.
    private var approvedRoute: Route {
        var route = draft
        for index in route.legs.indices {
            route.legs[index].assignments.removeAll { removed.contains($0.id) }
            for assignment in route.legs[index].assignments.indices {
                route.legs[index].assignments[assignment].after.removeAll { removed.contains($0) }
            }
        }
        route.legs.removeAll { $0.assignments.isEmpty }
        return route
    }

    private func approve() {
        guard !isRevising, !approvedRoute.assignments.isEmpty else { return }
        send(.approve(approvedRoute))
    }

    private func requestChanges() {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRevising else { return }
        send(.requestChanges(text))
        feedback = ""
    }

    private func toggleRemoved(_ id: String) {
        if removed.contains(id) {
            removed.remove(id)
        } else {
            removed.insert(id)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SectionHeader(title)
            content()
        }
    }
}

/// A bullet before the text, for assumptions.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            configuration.icon
                .font(.system(size: 4))
                .foregroundStyle(.dsTextTertiary)
            configuration.title
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
        }
    }
}
#endif
