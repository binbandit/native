import MCPClient
import SwiftUI

/// A one-line notice at the top of the page: something went wrong, or an undo for what just did.
struct MCPNotice: View {
    let text: String
    let tone: Badge.Tone
    var actionTitle: String?
    var action: () -> Void = {}

    private var color: Color {
        switch tone {
        case .danger: .dsDanger
        case .warning: .dsWarning
        default: .dsTextSecondary
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.lg) {
            Text(text)
                .settingsText(.body)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .transition(.opacity)
    }
}

/// What an empty list is, why, and the one action that fills it. Without an action it's only
/// information, so it's a note rather than a row with nothing to change.
struct MCPEmptyRow: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        if let actionTitle {
            SettingsRow(title, icon: "server.rack", description: Text(message)) {
                Button(actionTitle, action: action)
            }
        } else {
            SettingsNote(title, systemImage: "server.rack") { Text(message) }
        }
    }
}
