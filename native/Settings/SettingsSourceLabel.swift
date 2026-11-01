import SwiftUI

/// Shared attribution in New Tasks and the composer's task settings.
struct SettingsSourceLabel: View {
    enum Source: Equatable {
        case user
        case agent(String)
        case project(String)
        case mode(String)
        case native
        case policy
        case organization(String)

        var title: String {
            switch self {
            case .user: "Yours"
            case .project(let name): name
            case .mode(let name): "\(name) mode"
            case .native: "Native"
            case .policy: "Your policy"
            case .agent(let name): "\(name)'s own"
            case .organization(let name): name
            }
        }

        /// The user's own choice or Native's default: New Tasks leaves these untagged, so a tag
        /// always means someone else set the value.
        var isQuiet: Bool { self == .user || self == .native }

        var symbol: String? {
            switch self {
            case .organization: "building.2"
            case .policy: "lock"
            case .project: "folder"
            case .agent: "doc"
            case .user, .mode, .native: nil
            }
        }
    }

    let source: Source
    /// Only the glyph, where the row is too narrow for the name. A source without one keeps its name.
    var compact = false

    var body: some View {
        if source != .user {
            HStack(spacing: DS.Space.xs) {
                if let symbol = source.symbol { Image(systemName: symbol) }
                if !compact || source.symbol == nil { Text(source.title) }
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Source: \(source.title)")
            .help(compact ? source.title : "")
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
