import SwiftUI

/// Shared attribution in New Tasks and the composer's task settings.
struct SettingsSourceLabel: View {
    enum Source: Equatable {
        case user
        case agent(String)
        case organization(String)

        var title: String {
            switch self {
            case .user: "You"
            case .agent(let name): "\(name)'s own"
            case .organization(let name): name
            }
        }
    }

    let source: Source

    var body: some View {
        if source != .user {
            HStack(spacing: DS.Space.xs) {
                if case .organization = source { Image(systemName: "lock") }
                Text(source.title)
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Source: \(source.title)")
        }
    }
}

#if DEBUG
#Preview("Settings source - Personal, agent and managed") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSourceLabel(source: .user)
            SettingsSourceLabel(source: .agent("Codex"))
            SettingsSourceLabel(source: .organization("Northwind Federal IT"))
        }.padding(DS.Space.lg)
    }
}
#endif
