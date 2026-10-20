#if DEBUG && NATIVE_SESSION_CHROME_WIP
import SwiftUI

/// A header tool, open: its pane dropped over the conversation from under its fact, there while
/// you look and gone with Escape or another click on the fact. Nothing moves underneath.
struct SessionChromeShade: View {
    let tool: SessionChromeTool
    let context: SessionChromeContext
    let chrome: SessionChromeModel

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: DS.Radius.panel, bottomTrailingRadius: DS.Radius.panel, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: tool.systemImage)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                Text(tool.title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                SessionChromeFactBadge(fact: context.fact(for: tool))
                Spacer(minLength: DS.Space.md)
                Kbd("esc")
                IconButton("Close \(tool.title)", systemImage: "xmark") { close() }
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: SessionChromeMetrics.stripHeight)
            SeparatorLine()
            SessionChromeToolPane(tool: tool, context: context, chrome: chrome)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.dsBackground)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
        .dsShadow(DS.Shadow.floating)
        .background {
            // Escape closes it, wherever focus is in the window.
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }

    private func close() {
        withAnimation(.dsPanel) { chrome.close(.header) }
    }
}
#endif
