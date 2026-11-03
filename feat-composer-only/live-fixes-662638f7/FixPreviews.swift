import SwiftUI

#Preview("Composer fixes - Mode, Where, and twenty-line draft") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ComposerModeMenu(choices: ComposerRowPreviewFixtures.state.modes) { _ in }
            ComposerWhereMenu(choices: ComposerRowPreviewFixtures.state.locations) { _ in }
            ComposerFieldPreviewFixtures.field(
                (1...20).map { "Fixture draft line \($0): testing the scrolling composer." }.joined(separator: "\n"))
        }
    }
}
