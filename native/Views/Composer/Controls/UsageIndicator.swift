import ACP
import SwiftUI

/// How full the context window is; a click shows the token count and what the session has cost.
struct UsageIndicator: View {
    let usage: Usage

    @State private var isShowingDetails = false

    private var percent: String {
        usage.fractionUsed.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            HStack(spacing: DS.Space.sm) {
                ContextUsageRing(fraction: usage.fractionUsed)
                Text(percent)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: usage.fractionUsed))
            }
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .padding(.horizontal, DS.Space.xs)
            .frame(height: DS.Size.composerPill)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.dsStandard, value: usage.fractionUsed)
        .help("Context usage")
        .accessibilityLabel("Context: \(percent) used")
        .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
            details
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.xxl, verticalSpacing: DS.Space.sm) {
            GridRow {
                Text("Context")
                    .foregroundStyle(.dsTextSecondary)
                Text("\(usage.used.formatted()) of \(usage.size.formatted()) tokens")
                    .monospacedDigit()
            }
            if let cost = usage.cost {
                GridRow {
                    Text("Cost")
                        .foregroundStyle(.dsTextSecondary)
                    Text(cost.amount, format: .currency(code: cost.currency))
                        .monospacedDigit()
                }
            }
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextPrimary)
        .padding(DS.Space.lg)
    }
}
