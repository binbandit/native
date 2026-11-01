import ApprovalAnalysis
import SwiftUI

/// Literal text keeps whitespace and quoting. Wide hosts hang each explanation from its source
/// offset; narrow hosts stack those same fragments without shrinking the type.
struct ApprovalCommandDiagram: View {
    let analysis: ApprovalCommand
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Tabs and wide glyphs do not have the font's ordinary monospace advance.
            if analysis.command.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) {
                diagram.fixedSize(horizontal: true, vertical: true)
            }
            compact
        }
        .foregroundStyle(.dsTextPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Approval.commandInset)
        .padding(.top, DS.Approval.commandTop)
        .padding(.bottom, DS.Space.md)
        .accessibilityElement(children: .combine)
    }

    private func command(underlined: Bool) -> Text {
        var text = AttributedString(analysis.command)
        for part in analysis.parts {
            let start = text.characters.index(text.startIndex, offsetBy: part.range.lowerBound)
            let end = text.characters.index(text.startIndex, offsetBy: part.range.upperBound)
            if underlined {
                text[start..<end].underlineStyle = .init(pattern: .solid, color: part.destructive ? .dsDanger : nil)
            }
            if part.destructive { text[start..<end].foregroundColor = .dsDanger }
        }
        return Text(text).font(DS.Approval.commandFont)
    }

    private func x(_ part: ApprovalCommand.Part) -> CGFloat {
        CGFloat(part.range.lowerBound) * DS.Approval.monoAdvance
    }

    private var diagram: some View {
        VStack(alignment: .leading, spacing: 0) {
            command(underlined: false)
                .frame(height: DS.Approval.commandLine, alignment: .topLeading)
                .textSelection(.enabled)
                .overlay(alignment: .topLeading) {
                    // Drawn in the text's own coordinates, so each rule sits under its characters.
                    underlines(destructive: false).fill(Color.dsTextQuaternary)
                    underlines(destructive: true).fill(Color.dsDanger)
                }
            if analysis.parts.isEmpty {
                fallback
            } else {
                // The last part's explanation is the top row, so stems never cross.
                let parts = Array(analysis.parts.reversed())
                ApprovalAnnotationLayout {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { row, part in
                        explanation(part).font(.dsBody).foregroundStyle(.dsTextSecondary).fixedSize()
                            .layoutValue(key: ApprovalAnnotationLayout.Offset.self, value: x(part))
                            .layoutValue(key: ApprovalAnnotationLayout.Row.self, value: row)
                    }
                }
                .background(alignment: .topLeading) {
                    Path { path in
                        for (row, part) in parts.enumerated() {
                            let y = CGFloat(row) * DS.Approval.annotationLine + DS.Approval.annotationGap
                            path.move(to: CGPoint(x: x(part) + DS.Approval.rule / 2, y: 0))
                            path.addLine(to: CGPoint(x: x(part) + DS.Approval.rule / 2, y: y))
                            path.addLine(to: CGPoint(x: x(part) + DS.Approval.annotationStem, y: y))
                        }
                    }
                    .stroke(Color.dsTextQuaternary, lineWidth: DS.Approval.rule)
                }
                .frame(minWidth: CGFloat(analysis.command.count) * DS.Approval.monoAdvance, alignment: .leading)
            }
        }
    }

    private func underlines(destructive: Bool) -> Path {
        Path { path in
            for part in analysis.parts where part.destructive == destructive {
                path.addRect(
                    CGRect(
                        x: x(part), y: DS.Approval.commandLine - DS.Approval.rule,
                        width: CGFloat(part.range.count) * DS.Approval.monoAdvance, height: DS.Approval.rule))
            }
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            command(underlined: true).lineSpacing(DS.Approval.commandLineSpacing)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            ForEach(analysis.parts) { part in
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(String(Array(analysis.command)[part.range]))
                        .font(.dsMono)
                        .foregroundStyle(part.destructive ? Color.dsDanger : .dsTextPrimary)
                    explanation(part).font(.dsBody).foregroundStyle(.dsTextSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if analysis.parts.isEmpty { fallback }
        }
    }

    private func explanation(_ part: ApprovalCommand.Part) -> Text {
        var text = AttributedString(part.explanation)
        if let separator = part.explanation.range(of: " · ") {
            let count = part.explanation.distance(from: part.explanation.startIndex, to: separator.lowerBound)
            let end = text.characters.index(text.startIndex, offsetBy: count)
            text[text.startIndex..<end].foregroundColor = .dsTextPrimary
            text[text.startIndex..<end].font = .dsBodyMedium
            text[end...].foregroundColor = .dsTextTertiary
        }
        return Text(text)
    }

    private var fallback: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Rectangle().fill(DS.Approval.separator(colorScheme)).frame(height: DS.Approval.rule)
            Text(analysis.consequence).font(.dsBody).foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.top, DS.Space.md)
    }
}

#if DEBUG
#Preview("Approval command - force, routine, unknown, narrow") {
    DSPreviewPair {
        VStack {
            ApprovalCommandDiagram(analysis: ApprovalPreviewFixtures.force).frame(width: 552)
            ApprovalCommandDiagram(analysis: ApprovalPreviewFixtures.routine).frame(width: 552)
            ApprovalCommandDiagram(analysis: ApprovalPreviewFixtures.unknown).frame(width: 552)
            ApprovalCommandDiagram(analysis: ApprovalPreviewFixtures.force).frame(width: 300)
        }.padding(DS.Space.xl)
    }
}
#endif
