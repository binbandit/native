import SwiftUI

struct ComposerWhereMenu: View {
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
#Preview("Composer where menu - Folder or new branch") {
    DSPreviewPair { ComposerWhereMenu(choices: ComposerRowPreviewFixtures.state.locations) { _ in } }
}
#endif
