import SwiftUI

/// The sidebar's footer: a hairline, then Settings at the trailing edge. Help is the status bar's
/// "?" and the Help menu; agents' health lives on Home and in Settings ▸ Agents. While the status
/// bar shows, the footer shrinks to the bar's height, so the two stack as one quiet band with their
/// glyphs at the same size.
struct SidebarFooter: View {
    @Environment(StatusBarRegistry.self) private var statusBar: StatusBarRegistry?

    var body: some View {
        let isAboveStatusBar = statusBar?.isVisible == true
        HStack {
            Spacer(minLength: 0)
            SettingsButton()
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, isAboveStatusBar ? 0 : DS.Space.lg)
        .frame(height: isAboveStatusBar ? DS.Size.chromeBar : nil)
        .overlay(alignment: .top) {
            SeparatorLine()
                .padding(.horizontal, DS.Space.lg)
        }
    }
}

/// Opens Settings (a gear, "Settings ⌘,"). iPadOS has no Settings scene; the
/// app presents settings there itself, so the gear isn't shown.
private struct SettingsButton: View {
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        Button {
            settings.open()
        } label: {
            FooterGlyph(systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
    }
}

/// A footer icon: a 16pt muted glyph that brightens on hover, with no fill. The status
/// bar's glyphs (`StatusBarGlyph`) are the same size.
private struct FooterGlyph: View {
    let systemImage: String

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.dsCallout)
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .frame(width: DS.Size.chromeGlyph, height: DS.Size.chromeGlyph)
            .contentShape(.rect)
            .dsHitTarget(DS.Size.chromeGlyph)
            .trackHover($isHovered)
    }
}
