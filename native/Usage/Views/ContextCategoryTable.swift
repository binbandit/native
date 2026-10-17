import ACP
import SwiftUI

/// Every category of the window with its tokens and share, in the bar's order. It's the bar's
/// legend and its table at once: swatches match the segments.
struct ContextCategoryTable: View {
    let composition: ContextComposition

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Grid(alignment: .leading, horizontalSpacing: DS.Space.md, verticalSpacing: DS.Space.xs) {
                ForEach(composition.segments) { segment in
                    row(segment.name, tokens: DSFormat.tokens(segment.tokens), share: DSFormat.share(segment.tokens, of: composition.windowTokens)) {
                        // The free space is the bar's track, faint enough to need an edge here.
                        Swatch(color: segment.kind.color, isOutlined: segment.kind == .free)
                    }
                    .foregroundStyle(segment.kind == .free ? .dsTextSecondary : .dsTextPrimary)
                }
            }
            if !composition.deferred.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Loaded on demand, not in the window")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                    Grid(alignment: .leading, horizontalSpacing: DS.Space.md, verticalSpacing: DS.Space.xs) {
                        ForEach(composition.deferred, id: \.name) { category in
                            row(category.name, tokens: DSFormat.tokens(category.tokens), share: "") {
                                Swatch(color: .clear, isOutlined: true, isDashed: true)
                            }
                            .foregroundStyle(.dsTextSecondary)
                        }
                    }
                }
            }
        }
    }

    private func row(_ name: String, tokens: String, share: String, @ViewBuilder swatch: () -> some View) -> some View {
        GridRow {
            swatch()
            Text(name)
                .font(.dsBody)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(tokens)
                .font(.dsBody)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
            Text(share)
                .font(.dsCaption)
                .monospacedDigit()
                .foregroundStyle(.dsTextTertiary)
                .frame(width: UsageMetrics.shareColumnWidth, alignment: .trailing)
        }
    }
}

/// A category's color key, shaped like the bar it stands for.
private struct Swatch: View {
    let color: Color
    var isOutlined = false
    var isDashed = false

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(color)
            .overlay {
                if isOutlined {
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .strokeBorder(.dsBorder, style: StrokeStyle(lineWidth: 1, dash: isDashed ? [2, 1] : []))
                }
            }
            .frame(width: UsageMetrics.swatchSize, height: UsageMetrics.swatchSize)
            .accessibilityHidden(true)
    }
}
