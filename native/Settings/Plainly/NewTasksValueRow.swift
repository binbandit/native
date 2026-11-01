import ACP
import Modes
import NativePolicy
import SwiftUI

struct NewTasksValueRow: View {
    let model: NewTasksDefaultsModel
    let setting: AgentSessionDefaults.Setting
    var mode = Mode.build
    @Environment(\.undoManager) private var undoManager
    @Environment(PolicyCenter.self) private var policyCenter: PolicyCenter?
    @State private var showsSource = false

    private var policy: NativePolicy { policyCenter?.policy ?? PolicyCenter.shared.policy }
    private var receipt: NewTasksSettingReceipt { model.receipt(setting, policy: policy, mode: mode) }
    private var choices: [ConfigOption.SelectOption] { model.choices(setting) }

    var body: some View {
        SettingsRow(
            id: AgentDefaultsRow.settingRowID(agentID: model.agent, setting: setting), receipt.title,
            detail: unavailableNote
        ) {
            HStack(spacing: DS.Space.md) {
                // Reset clears a choice saved here; one inherited from All projects is changed there.
                if receipt.unavailable, model.stored(setting) != nil {
                    Button("Reset") { model.set(nil, for: setting, undoManager: undoManager) }
                }
                NewTasksSourceControl(receipt: receipt, showsSource: $showsSource) {
                    NewTasksValueMenu(label: receipt.title, value: valueTitle, isDefault: receipt.isDefault) {
                        Button("Follow \(model.project == nil ? model.agentName : "All projects")") {
                            model.set(nil, for: setting, undoManager: undoManager)
                        }
                        Divider()
                        ForEach(choices, id: \.value) { choice in
                            Button {
                                model.set(choice.value, for: setting, undoManager: undoManager)
                            } label: {
                                if choice.value == model.stored(setting) {
                                    Label(choice.name, systemImage: "checkmark")
                                } else {
                                    Text(choice.name)
                                }
                            }
                        }
                        Divider()
                        Button("Why This Value…") { showsSource = true }
                        Button("Reset") { model.set(nil, for: setting, undoManager: undoManager) }
                            .disabled(model.stored(setting) == nil)
                    }
                }
            }
            .contextMenu {
                Button("Why This Value…") { showsSource = true }
                Button("Reset") { model.set(nil, for: setting, undoManager: undoManager) }
                    .disabled(model.stored(setting) == nil)
            }
        }
    }

    /// Under the label, in the row: what happened to a saved choice the agent stopped offering.
    private var unavailableNote: Text? {
        receipt.unavailableNote.map { Text($0).foregroundStyle(.dsTextTertiary) }
    }

    private var valueTitle: String {
        if choices.isEmpty {
            return model.hasReportedOptions ? "Not offered by \(model.agentName)" : "Not reported yet"
        }
        if !receipt.unavailable, !receipt.modeOverrides, model.stored(setting) == nil, model.project == nil {
            return model.followTitle(setting)
        }
        return receipt.value
    }
}

#if DEBUG
#Preview("New Tasks - Values, unavailable and empty") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ForEach(["populated", "empty", "unavailable"], id: \.self) { state in
                SettingsRowGroup {
                    ForEach(AgentSessionDefaults.Setting.allCases, id: \.self) { setting in
                        NewTasksValueRow(model: NewTasksPreviewFixtures.model(state: state), setting: setting)
                    }
                }
            }
        }.settingsPreviewPage()
    }
    .environment(\.settingsPlainly, true)
}
#endif
