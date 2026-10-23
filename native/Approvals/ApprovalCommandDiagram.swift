import ApprovalAnalysis
import SwiftUI

/// Literal text keeps whitespace and quoting. Wide hosts hang each explanation from its source
/// offset; narrow hosts stack those same fragments without shrinking the type.
struct ApprovalCommandDiagram: View {
    let analysis: ApprovalCommand

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

    private var command: Text {
        var text = AttributedString(analysis.command)
        for part in analysis.parts {
            let start = text.characters.index(text.startIndex, offsetBy: part.range.lowerBound)
            let end = text.characters.index(text.startIndex, offsetBy: part.range.upperBound)
            text[start..<end].underlineStyle = .single
        }
        return Text(text).font(DS.Approval.commandFont)
    }

    private var diagram: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(analysis.command).font(DS.Approval.commandFont)
                .frame(height: DS.Approval.commandLine, alignment: .topLeading)
                .textSelection(.enabled)
                .overlay(alignment: .bottomLeading) {
                    ForEach(analysis.parts) { part in
                        Rectangle().fill(part.destructive ? Color.dsDanger : .dsTextQuaternary)
                            .frame(width: CGFloat(part.range.count) * DS.Approval.monoAdvance, height: DS.Approval.rule)
                            .offset(x: CGFloat(part.range.lowerBound) * DS.Approval.monoAdvance)
                    }
                    .accessibilityHidden(true)
                }
            if !analysis.parts.isEmpty {
                let parts = Array(analysis.parts.reversed())
                ZStack(alignment: .topLeading) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { row, part in
                        let x = CGFloat(part.range.lowerBound) * DS.Approval.monoAdvance
                        let y = CGFloat(row) * DS.Approval.annotationLine + DS.Approval.annotationGap
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: y))
                            path.addLine(to: CGPoint(x: x + DS.Approval.annotationStem, y: y))
                        }
                        .stroke(part.destructive ? Color.dsDanger : .dsTextQuaternary, lineWidth: DS.Approval.rule)
                        Text(part.explanation)
                            .font(.dsBody).foregroundStyle(.dsTextSecondary).fixedSize()
                            .padding(.leading, x + DS.Approval.annotationGap)
                            .padding(.top, CGFloat(row) * DS.Approval.annotationLine + DS.Space.xxs)
                    }
                }
                .frame(width: diagramWidth, height: CGFloat(parts.count) * DS.Approval.annotationLine)
            } else {
                fallback
            }
        }
    }

    private var diagramWidth: CGFloat {
        let longest =
            analysis.parts.map { part in
                CGFloat(part.range.lowerBound) * DS.Approval.monoAdvance
                    + CGFloat(part.explanation.count) * DS.Space.sm + DS.Approval.annotationGap
            }.max() ?? 0
        return max(CGFloat(analysis.command.count) * DS.Approval.monoAdvance, longest)
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            command.fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            ForEach(analysis.parts) { part in
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(String(Array(analysis.command)[part.range]))
                        .font(.dsMono).underline()
                        .foregroundStyle(part.destructive ? Color.dsDanger : .dsTextPrimary)
                    Text(part.explanation).font(.dsBody).foregroundStyle(.dsTextSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if analysis.parts.isEmpty { fallback }
        }
    }

    private var fallback: some View {
        Text(analysis.consequence).font(.dsBody).foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true).padding(.top, DS.Space.md)
    }
}

#if DEBUG
#Preview("Approval command - wide and narrow") {
    DSPreviewPair {
        VStack {
            ApprovalCommandDiagram(analysis: ApprovalPreviewFixtures.force).frame(width: 900)
            ApprovalCommandDiagram(analysis: ApprovalPreviewFixtures.routine).frame(width: 360)
            ApprovalCommandDiagram(analysis: ApprovalPreviewFixtures.unknown).frame(width: 360)
        }.padding(DS.Space.xl)
    }
}
#endif
