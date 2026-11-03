import SwiftUI

struct ComposerModeMenu: View {
    let choices: [ComposerRowState.Choice]
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(choices) { choice in
                ComposerRowMenuOption(choice: choice) { choose(choice.id) }
            }
        }
        .padding(DS.Space.sm)
        .frame(width: DS.ComposerRow.menuWidth)
        .background(.dsOverlay)
    }
}

#if DEBUG
#Preview("Composer mode menu - Four modes") {
    DSPreviewPair { ComposerModeMenu(choices: ComposerRowPreviewFixtures.state.modes) { _ in } }
}
#endif
