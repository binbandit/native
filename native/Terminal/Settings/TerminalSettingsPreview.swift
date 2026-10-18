import SwiftUI
import Terminal

/// A few lines of a shell session in the chosen font and the terminal's colors.
struct TerminalSettingsPreview: View {
    let settings: TerminalSettings
    let colors: TerminalColors

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text("\(color(2, "native"))\(color(nil, " % git status"))")
            color(nil, "On branch main")
            Text("\(color(nil, "  modified:   "))\(color(1, "docs/terminal.md"))")
            Text("\(color(nil, "  new file:   "))\(color(2, "native/Terminal/"))")
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.lg)
        .background(Color(colors.chrome.background), in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.dsSeparator)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the terminal font")
    }

    private var font: Font {
        let size = settings.fontSize
        guard let family = settings.fontFamily else {
            return Font(DSTypography.nsFont(size: size, design: .mono))
        }
        return .custom(family, fixedSize: size)
    }

    /// `text` in palette color `index`, or the default text color.
    private func color(_ index: Int?, _ text: String) -> Text {
        let rgb = index.map { colors.palette[$0] } ?? colors.chrome.foreground
        return Text(text).foregroundStyle(Color(rgb))
    }
}

extension Color {
    init(_ rgb: TerminalRGB) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}
