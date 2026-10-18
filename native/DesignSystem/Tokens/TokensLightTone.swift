import SwiftUI

// The white that light mode is drawn on. Paper is a crisp white; Wool a warm, slightly desaturated
// off-white for people who find paper white glaring. Wool is a whole token set, not a tint: every
// light neutral (layers, fills, borders, the sidebar's backdrop) moves together, and text and
// status colors step darker by just enough to keep Paper's contrast (TokensColor.swift). Dark mode
// is the same under both.

/// The white light mode is drawn on.
public nonisolated enum DSLightTone: String, CaseIterable, Identifiable, Sendable {
    /// Crisp white, the default.
    case paper
    /// A warm off-white.
    case wool

    public var id: Self { self }

    public var title: String {
        switch self {
        case .paper: "Paper"
        case .wool: "Wool"
        }
    }
}

nonisolated extension EnvironmentValues {
    /// The white light mode is drawn on. Set it with `.dsLightTone(_:)`.
    @Entry public var dsLightTone: DSLightTone = .paper
}

extension View {
    /// Sets the white this window's light mode is drawn on. Put it on each window's root, next to
    /// `.dsAccentPalette(themeID:)`.
    public func dsLightTone(_ tone: DSLightTone) -> some View {
        environment(\.dsLightTone, tone)
    }
}

/// A token whose light value depends on the light tone: Paper and dark come from the base color,
/// Wool from its own value.
nonisolated struct DSTonedStyle: ShapeStyle, Hashable {
    let base: Color
    let wool: Color.Resolved

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        if environment.colorScheme == .light, environment.dsLightTone == .wool {
            wool
        } else {
            base.resolve(in: environment)
        }
    }
}
