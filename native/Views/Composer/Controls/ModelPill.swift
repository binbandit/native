import ACP
import SwiftUI

/// The model picker's chip, with the effort meter inside it; clicking the meter steps the effort up.
struct ModelPill: View {
    let model: SelectSetting?
    let effort: SelectSetting?
    let switches: [SelectSetting]
    @Binding var isPickerOpen: Bool
    let onSet: (SelectSetting, String) -> Void
    let onCycleEffort: () -> Void

    private var modelName: String {
        model?.currentName ?? "Default"
    }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            HStack(spacing: DS.Space.md) {
                HStack(spacing: DS.Space.xs) {
                    Text(model?.shortModelName ?? "Model")
                    if switches.contains(where: \.isOn) {
                        Image(systemName: "bolt.fill")
                            .font(.dsMicro)
                            .foregroundStyle(.dsTextSecondary)
                    }
                }
                if let effort, !effort.levels.isEmpty {
                    effortMeter(effort)
                }
            }
        }
        .buttonStyle(.pill(isOpen: isPickerOpen))
        .help("Model: \(modelName) (⇧⌘E)")
        .accessibilityLabel("Model: \(modelName)")
        .popover(isPresented: $isPickerOpen, arrowEdge: .top) {
            ModelPicker(model: model, effort: effort, switches: switches, onSet: onSet) {
                isPickerOpen = false
            }
            .dsPopoverBackground()
        }
    }

    private func effortMeter(_ effort: SelectSetting) -> some View {
        // It only steps up (`ComposerSettings.nextEffort`): at the highest level, or on a value it can't
        // place, a click does nothing, and a lower effort is chosen in the picker.
        let canStepUp = effort.option.valueAfterCurrent != nil
        let isHighest = !canStepUp && effort.current != nil
        return Button(action: onCycleEffort) {
            EffortBars(total: effort.levels.count, level: effort.litLevel ?? 0, isMuted: effort.litLevel == nil)
                // Small bars, so the click target reaches past them.
                .contentShape(.rect.inset(by: -DS.Space.sm))
        }
        .buttonStyle(.plain)
        .help(
            canStepUp
                ? "Effort: \(effort.currentName). Click for the next level."
                : isHighest
                    ? "Effort: \(effort.currentName), the highest. Choose a lower one in the model picker."
                    : "Effort: \(effort.currentName)."
        )
        .accessibilityLabel("Effort: \(effort.currentName)")
        .accessibilityHint(canStepUp ? "Switches to the next effort level" : "")
    }
}

#if DEBUG
#Preview("Model pill") {
    let settings = ComposerPreviewFixtures.settings
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ModelPill(
                model: settings.model, effort: settings.effort, switches: settings.modelSwitches,
                isPickerOpen: .constant(false), onSet: { _, _ in }, onCycleEffort: {})
            ModelPill(
                model: settings.model, effort: nil, switches: [], isPickerOpen: .constant(true), onSet: { _, _ in },
                onCycleEffort: {})
            ModelPill(
                model: nil, effort: settings.effort, switches: [], isPickerOpen: .constant(false), onSet: { _, _ in },
                onCycleEffort: {})
        }
    }
}
#endif
