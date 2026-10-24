import ACP
import SwiftUI

/// The agent's todo list as the composer's top section. Collapsed,
/// it shows only the step in progress (or the next one); expanded, every step.
struct ComposerPlanSection: View {
    enum Presentation { case progress, review }

    let plan: PlanProgress
    /// Whether the agent is working right now, so the current step shows a spinner.
    let isWorking: Bool
    @Binding var isExpanded: Bool
    var presentation: Presentation = .progress

    var body: some View {
        switch presentation {
        case .progress: progress
        case .review: review
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(
                Array(plan.entries.prefix(isExpanded ? plan.entries.count : DS.PlanReview.visibleSteps).enumerated()),
                id: \.offset
            ) { index, entry in
                row(entry, number: index + 1)
            }
            if plan.entries.count > DS.PlanReview.visibleSteps {
                Button(
                    isExpanded
                        ? "Show fewer steps" : "Show \(plan.entries.count - DS.PlanReview.visibleSteps) more steps"
                ) {
                    withAnimation(.dsDisclosure) { isExpanded.toggle() }
                }
                .buttonStyle(.plain).font(.dsBody).foregroundStyle(.dsTextSecondary)
                .dsHitTarget(DS.Size.controlXS)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .padding(.leading, DS.PlanReview.numberWidth + DS.Space.md)
            }
        }
        .padding(.horizontal, DS.PlanReview.horizontalInset)
        .padding(.vertical, DS.PlanReview.verticalInset)
        .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control))
    }

    private var progress: some View {
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

    private func row(_ entry: PlanEntry, number: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            if let number {
                Text("\(number)").font(.dsMonoCaption).foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.PlanReview.numberWidth, alignment: .leading)
            } else {
                StepIndicator(status: entry.status, isWorking: isWorking)
                    .frame(width: ComposerMetrics.stepSlotWidth, height: ComposerMetrics.stepSlotWidth)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + DS.Space.xs }
            }
            Text(entry.content)
                .font(number == nil ? .dsBody : DS.PlanReview.entryFont)
                .lineSpacing(number == nil ? 0 : DS.PlanReview.lineSpacing)
                .fixedSize(horizontal: false, vertical: presentation == .review)
                .foregroundStyle(entry.status == .completed ? .dsTextTertiary : .dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: number == nil ? nil : DS.PlanReview.rowHeight, alignment: .top)
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
#Preview("Plan review - Five steps and expanded") {
    DSPreviewPair {
        ComposerPlanSection(
            plan: PlanProgress(entries: ComposerPreviewFixtures.plan), isWorking: false,
            isExpanded: .constant(false), presentation: .review
        )
        .padding(DS.Space.xl).frame(width: DS.HomeNext.column)
    }
}

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
