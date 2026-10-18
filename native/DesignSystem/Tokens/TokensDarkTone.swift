import SwiftUI

// The black that dark mode is drawn on. Standard is a deep neutral: the content pane at #0D0D0E,
// with the sidebar, the window's chrome and code wells a step deeper at #070708. True Black puts the
// content, sidebar and chrome on pure black for OLED screens, where black pixels stay off, and lifts
// separators, borders, the selection and raised surfaces just enough to stay readable there. Like
// Wool, True Black is a whole set of layers and lines (TokensColor.swift); text, accent and status
// colors are Standard's, which only gain contrast on black. Light mode is the same under both.

/// The black dark mode is drawn on.
public nonisolated enum DSDarkTone: String, CaseIterable, Identifiable, Sendable {
    /// A deep neutral, the default.
    case standard
    /// Pure black, for OLED screens.
    case trueBlack

    public var id: Self { self }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .trueBlack: "True Black"
        }
    }
}

nonisolated extension EnvironmentValues {
    /// The black dark mode is drawn on. Set it with `.dsDarkTone(_:)`.
    @Entry public var dsDarkTone: DSDarkTone = .standard
}

extension View {
    /// Sets the black this window's dark mode is drawn on. Put it on each window's root, next to
    /// `.dsLightTone(_:)`.
    public func dsDarkTone(_ tone: DSDarkTone) -> some View {
        environment(\.dsDarkTone, tone)
    }
}
