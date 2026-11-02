import SwiftUI

/// New-task address menus reuse the composer's agent and model choices.
struct ComposeAgentPicker: View {
    let model: AppModel
    var maxHeight = DS.ComposeTask.popoverMaxHeight

    var body: some View {
        let adapter = ComposerRowModelAdapter(app: model)
        let actions = adapter.actions(attach: {}, context: {}, send: {})
        ComposerAgentModelMenu(
            agents: adapter.state.agents, effort: adapter.state.effort,
            chooseModel: actions.chooseModel, chooseEffort: actions.chooseEffort,
            close: { model.quickEntry.picker = nil })
    }
}

#if DEBUG
#Preview("Compose - Agent and model") {
    DSPreviewPair { ComposeAgentPicker(model: ComposeTaskPreviewFixtures.model("agents")) }
}
#endif
