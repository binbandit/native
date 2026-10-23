import AppAppearance
import SwiftUI

struct PlayfulSpinnersSettingsRow: View {
    static let rowID = SettingsRowID("appearance.playful-spinners")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Playful spinners",
            description: "A random dot-grid animation for each task.",
            keywords: ["working", "loader", "dots", "animation", "random", "motion"])
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(
                id: Self.rowID, "Playful spinners",
                description: Text("A random dot-grid animation for each task, kept for that task."),
                detail: reduceMotion ? Text("Reduce Motion is on, so the dot grid stays still.") : nil
            ) {
                SettingsSwitch(
                    "Playful spinners",
                    isOn: Binding(
                        get: { model.workingSpinners.isEnabled },
                        set: { model.workingSpinners.setEnabled($0) }))
            }
            if model.workingSpinners.isEnabled {
                WorkingSpinnerSamples()
            }
        }
    }
}

#if DEBUG
#Preview("Playful spinners - Off") {
    DSPreviewPair {
        PlayfulSpinnersSettingsRow().settingsPreviewPage()
    }
    .environment(AppModel.preview(.empty))
}

#Preview("Playful spinners - On") {
    let app = AppModel.preview(.empty)
    app.workingSpinners.setEnabled(true)
    return DSPreviewPair {
        PlayfulSpinnersSettingsRow().settingsPreviewPage()
    }
    .environment(app)
}

#endif
