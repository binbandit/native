import ACP
import SwiftUI

/// Where instructions went to the agent ahead of a prompt (a mode's, `PromptPreamble`): one quiet
/// line across the transcript, "Debug mode", rather than the instructions themselves.
struct PromptPreambleMarker: View {
    let marker: PromptPreamble.Marker

    var body: some View {
        HStack(spacing: DS.Space.md) {
            SeparatorLine()
            Group {
                if let symbol = marker.symbol {
                    Label(marker.label, systemImage: symbol)
                } else {
                    Text(marker.label)
                }
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .lineLimit(1)
            .fixedSize()
            SeparatorLine()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Switched to \(marker.label)")
        .help("Native gave \(marker.label)'s instructions to the agent with this message")
    }
}
