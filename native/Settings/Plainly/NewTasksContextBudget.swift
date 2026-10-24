import SwiftUI
import TaskDefaults

/// What a new task loads before its first message, against the model's context window: one
/// headline, a hairline bar, the legend and one caveat. The rest of the caveats wait in a popover.
struct NewTasksContextBudget: View {
    let budget: TaskContextBudget
    @State private var showsCaveats = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Before your first message")
                    Spacer(minLength: DS.Space.md)
                    summary.foregroundStyle(.dsTextPrimary)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Before your first message")
                    summary.foregroundStyle(.dsTextPrimary)
                }
            }
            .font(DS.Settings.caption)
            .foregroundStyle(.dsTextSecondary)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(TaskContextBudget.Part.Kind.allCases, id: \.self) { kind in
                        Rectangle().fill(color(kind))
                            .frame(width: geometry.size.width * budget.fraction(for: kind))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.dsFill)
                .clipped()
            }
            .frame(height: DS.Settings.contextBarHeight)
            .accessibilityHidden(true)
            if budget.parts.isEmpty {
                note
            } else {
                legendAndNote
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The count, then the window in a lighter tone. A "+" in the legend marks what's uncounted.
    private var summary: Text {
        guard budget.knownTokens > 0 else { return Text("Not counted yet") }
        let of = budget.window.map { " of \(DSFormat.tokens($0)) tokens" } ?? " tokens"
        return Text("about \(DSFormat.tokens(budget.knownTokens))\(Text(of).foregroundStyle(.dsTextTertiary))")
    }

    private var caveats: [String] {
        var lines = ["Counts are estimates until the new task reports them."]
        if budget.unknownCount > 0 {
            lines.append("A + marks items not counted yet. The agent may add built-in or conditional context.")
        }
        if budget.window == nil { lines.append("The context window appears after this model reports it.") }
        lines.append(
            "Instruction files and conditional context stay under the agent's control. Skill estimates cover their names and descriptions, before a skill is opened."
        )
        return lines
    }

    /// The legend beside its note, stacking when the page is narrow. An empty budget has no legend.
    private var legendAndNote: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.lg) {
                legend
                Spacer(minLength: DS.Space.md)
                note
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.lg) { legend }
                note
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                legend
                note
            }
        }
    }

    private var note: some View {
        Button {
            showsCaveats = true
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text("Counted by the agent where it can; estimated otherwise.")
                Image(systemName: "info.circle").font(.dsMicro)
            }
            .font(DS.Settings.caption).foregroundStyle(.dsTextTertiary)
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.Settings.controlHeight)
        .accessibilityHint("Shows how the counts are made")
        .popover(isPresented: $showsCaveats) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(caveats, id: \.self) { Text($0) }
            }
            .font(DS.Settings.caption)
            .foregroundStyle(.dsTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(DS.Space.lg)
            .frame(width: DS.Settings.sourceStackWidth)
            .dsPopoverBackground()
        }
    }

    @ViewBuilder private var legend: some View {
        ForEach(TaskContextBudget.Part.Kind.allCases, id: \.self) { kind in
            HStack(spacing: DS.Space.xs) {
                Rectangle().fill(color(kind))
                    .frame(width: DS.Settings.contextLegendSize, height: DS.Settings.contextBarHeight)
                Text(kind.rawValue.capitalized)
                Text(legendCount(kind)).monospacedDigit()
            }
            .font(DS.Settings.caption).foregroundStyle(.dsTextTertiary)
        }
    }

    private func legendCount(_ kind: TaskContextBudget.Part.Kind) -> String {
        let tokens = budget.tokens(for: kind)
        let unknown = budget.parts.contains { $0.kind == kind && $0.included && $0.tokens == nil }
        if unknown && tokens == 0 { return "-" }
        return DSFormat.tokens(tokens) + (unknown ? "+" : "")
    }

    private func color(_ kind: TaskContextBudget.Part.Kind) -> Color {
        switch kind {
        case .tools: .dsTextPrimary
        case .instructions: .dsTextSecondary
        case .skills: .dsTextTertiary
        }
    }
}

#if DEBUG
#Preview("New Tasks - Context, estimated and unknown") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xxl) {
            NewTasksContextBudget(budget: NewTasksPreviewFixtures.budget)
            NewTasksContextBudget(budget: .init(parts: [.init(.tools, tokens: nil)]))
        }.padding(DS.Space.lg).frame(width: DS.Settings.pageWidth)
    }
}
#endif
