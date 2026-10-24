import CodeThemes
import SwiftUI

/// One excerpt, in the effective window theme. Narrow columns keep indentation and fade the edge.
struct CodeThemeCardWell: View {
    let specimen: SpecimenLine
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.dsCodeThemes) private var themes
    @Environment(\.dsCodeStrongFont) private var strongFont

    private var colors: DSCodeColors {
        DSCodeColors(.code(colorScheme: scheme, lightTone: lightTone, darkTone: darkTone, themes: themes), on: .sunken)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text(specimen.file).foregroundStyle(colors.color(.foreground))
                Text(
                    specimen.isSample
                        ? "Sample in \(specimen.languageName)" : "\(specimen.project) · your latest change"
                )
                .foregroundStyle(colors.color(.comment))
            }
            .font(.dsBody)
            .frame(height: DS.Appearance.headerHeight)
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, DS.Space.md)
            .fixedSize(horizontal: true, vertical: false)
            ForEach(0..<2, id: \.self) { index in
                diffLine(specimen.deleted.indices.contains(index) ? specimen.deleted[index] : nil, added: false)
            }
            ForEach(0..<2, id: \.self) { index in
                diffLine(specimen.added.indices.contains(index) ? specimen.added[index] : nil, added: true)
            }
            Rectangle().fill(colors.color(.foreground).opacity(DS.Appearance.separatorOpacity))
                .frame(height: DS.Settings.hairline)
                .padding(.horizontal, DS.Space.xl)
                .padding(.vertical, DS.Space.md)
            HStack(spacing: 0) {
                Color.clear.frame(width: DS.Appearance.numberWidth * 2 + DS.Appearance.markerWidth)
                Text("\(specimen.project) ❯ ").foregroundStyle(colors.color(.comment))
                Text(specimen.testCommand).foregroundStyle(colors.color(.foreground))
                Text("  ✓ 14 pass  0 fail").foregroundStyle(
                    Color(colors.palette.ansiColors(for: scheme == .dark ? .dark : .light)[2]))
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: DS.Appearance.codeLineHeight)
        }
        .codeTextStyle()
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Appearance.wellBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: DS.Appearance.fadeWidth)
            }
        }
        .background(.dsCodeBlockBackground)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            specimen.isSample
                ? "Code theme preview. Sample in \(specimen.languageName), with a diff and a sample test run."
                : "Code theme preview. \(specimen.file) in \(specimen.project), your latest change, with a sample test run."
        )
    }

    private func diffLine(_ line: SpecimenLine.Line?, added: Bool) -> some View {
        HStack(spacing: 0) {
            number(added ? nil : line?.number)
            number(added ? line?.number : nil)
            Text(line == nil ? " " : added ? "+" : "-")
                .foregroundStyle(Color(added ? colors.palette.insertedForeground : colors.palette.deletedForeground))
                .frame(width: DS.Appearance.markerWidth)
            if let line {
                Text(
                    colors.text(
                        CodeHighlighter.segments(line.text, language: specimen.language), strongFont: strongFont)
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
        .frame(height: DS.Appearance.codeLineHeight)
        .background(Color(added ? colors.palette.insertedBackground : colors.palette.deletedBackground))
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? " ")
            .foregroundStyle(colors.color(.foreground).opacity(DS.Appearance.numberOpacity))
            .padding(.trailing, DS.Space.md)
            .frame(width: DS.Appearance.numberWidth, alignment: .trailing)
    }
}

#if DEBUG
#Preview("Appearance - Sample code and narrow fade") {
    DSPreviewPair { CodeThemeCardWell(specimen: .sample()).frame(width: 320) }
}
#endif
