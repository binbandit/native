import ACP
import SwiftUI

/// The agent's todo list as the composer's top section. Collapsed,
/// it shows only the step in progress (or the next one); expanded, every step.
struct ComposerPlanSection: View {
    let plan: PlanProgress
    /// Whether the agent is working right now, so the current step shows a spinner.
    let isWorking: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            CappedHeightScrollView(maxHeight: ComposerMetrics.planMaxHeight) {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    ForEach(Array(plan.visibleEntries(isExpanded: isExpanded).enumerated()), id: \.offset) { _, entry in
                        row(entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.xxs)
            }
            Button {
                withAnimation(.dsDisclosure) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Text(verbatim: "\(plan.completedCount)/\(plan.entries.count)")
                        .monospacedDigit()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.dsMicro)
                }
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Show only the current step" : "Show the whole plan")
            .accessibilityLabel(isExpanded ? "Collapse plan" : "Expand plan")
        }
        // The section's 8pt padding plus the list's own 4pt.
        .padding(DS.Space.lg)
    }

    private func row(_ entry: PlanEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            StepIndicator(status: entry.status, isWorking: isWorking)
                .frame(width: ComposerMetrics.stepSlotWidth, height: ComposerMetrics.stepSlotWidth)
                // Center the indicator on the first line of text.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + DS.Space.xs }
            Text(entry.content)
                .font(.dsBody)
                .foregroundStyle(entry.status == .completed ? .dsTextTertiary : .dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Step markers: a loader on the step being worked on, an accent dot when done, a muted
/// dot otherwise.
private struct StepIndicator: View {
    let status: PlanEntry.Status
    let isWorking: Bool

    var body: some View {
        switch status {
        case .inProgress where isWorking:
            // The one loader family (docs/product-quality.md), as PlanView uses.
            DotGridLoader(pattern: .waiting)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
        case .completed:
            dot(.dsAccent)
        case .pending, .inProgress:
            dot(.dsTextTertiary)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: ComposerMetrics.stepDotSize, height: ComposerMetrics.stepDotSize)
    }
}

#if DEBUG
#Preview("Plan section") {
    let plan = PlanProgress(entries: ComposerPreviewFixtures.plan)
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerSurface {
                ComposerPlanSection(plan: plan, isWorking: true, isExpanded: .constant(false))
            }
            ComposerSurface {
                ComposerPlanSection(plan: plan, isWorking: true, isExpanded: .constant(true))
            }
            // Stopped between steps: the current step shows a dot, not the loader.
            ComposerSurface {
                ComposerPlanSection(plan: plan, isWorking: false, isExpanded: .constant(true))
            }
        }
        .frame(width: 560)
    }
}
#endif
