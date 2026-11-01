import SwiftUI

/// A tool open over the conversation, dropped from under the header: a fact's tool, or a side
/// tool while the window is too narrow to read it beside the conversation. Escape, Close or
/// another click on its fact puts it away; nothing under it moves.
struct SessionToolsShade: View {
    let tool: SessionToolContribution
    let context: SessionToolContext
    let close: () -> Void

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: DS.Radius.panel, bottomTrailingRadius: DS.Radius.panel, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: tool.systemImage)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                Text(tool.title)
                    .lineLimit(1)
                    .help(tool.title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                SessionToolFactAccessory(accessory: tool.fact(context)?.accessory)
                    .fixedSize()
                Spacer(minLength: DS.Space.md)
                Kbd("esc")
                IconButton("Close \(tool.title)", systemImage: "xmark", action: close)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.SessionTools.stripHeight)
            SeparatorLine()
            tool.pane?(context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.dsBackground)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsBorder) }
        .dsShadow(DS.Shadow.floating)
        .background {
            // Escape puts it away wherever focus is, for as long as it's open.
            Button("Close \(tool.title)", action: close)
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }
}

#if DEBUG
#Preview("Changes overlay - Narrow") {
    DSPreviewPair {
        if let context = SessionToolsPreviewFixtures.context {
            SessionToolsShade(tool: SessionToolsPreviewFixtures.changes, context: context, close: {})
                .frame(width: 340, height: 480)
        }
    }
}
#endif
