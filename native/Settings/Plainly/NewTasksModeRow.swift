import Modes
import SwiftUI

struct NewTasksModeRow: View {
    private let library = ModeLibrary.shared

    var body: some View {
        SettingsRow(id: .modesDefault, "Mode") {
            SettingsSelect(
                label: "Mode",
                selection: Binding(
                    get: { library.startingMode.id }, set: { library.defaultMode = $0 }),
                options: (Mode.builtIn + library.custom).map { .init(value: $0.id, title: $0.name) })
        }
    }
}

#if DEBUG
#Preview("New Tasks - Mode") {
    DSPreviewPair { SettingsRowGroup { NewTasksModeRow() }.settingsPreviewPage() }
        .environment(\.settingsPlainly, true)
}
#endif
