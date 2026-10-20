import SwiftUI

// The one place today's composer surface gives way to a prototype direction (`-composerDesign`, DEBUG
// builds only).
extension ComposerView {
    /// Today's surface, or with `-composerDesign` in a DEBUG build, a prototype direction's.
    @ViewBuilder
    func designedSurface(_ settings: ComposerSettings, suggestions: ComposerSuggestions?) -> some View {
        #if DEBUG
        if let direction = ComposerDirection.launchChoice {
            directionSurface(direction, settings: settings, suggestions: suggestions)
        } else {
            surface(settings, suggestions: suggestions)
        }
        #else
        surface(settings, suggestions: suggestions)
        #endif
    }

    /// Whether the slash and file lists float above the composer.
    var floatsListedSuggestions: Bool {
        #if DEBUG
        floatsSuggestions
        #else
        true
        #endif
    }
}
