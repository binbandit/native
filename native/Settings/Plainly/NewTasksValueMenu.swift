import SwiftUI

/// The pop-up every New Tasks value uses: the value and an up-down chevron, with no frame or inset,
/// so every chevron on the page shares one trailing edge. A value left at its default reads muted.
struct NewTasksValueMenu<Items: View>: View {
    let label: String
    let value: String
    var isDefault = false
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: DS.Space.sm) {
                Text(value).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.dsMicro)
            }
            .font(DS.Settings.body)
            .foregroundStyle(isDefault ? .dsTextSecondary : .dsTextPrimary)
            .frame(minHeight: DS.Settings.controlHeight)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        // A long value truncates within the row rather than pushing past it.
        .fixedSize(horizontal: false, vertical: true)
        .dsHitTarget(DS.Settings.controlHeight)
        // The keyboard focus ring follows the value, as on every other settings select.
        .settingsFocusShape(RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

extension NewTasksValueMenu {
    /// A pop-up choosing one of `options`, the current one checked.
    init<Value: Hashable>(
        label: String, selection: Binding<Value>, options: [SettingsSelect<Value>.Option], isDefault: Bool
    ) where Items == NewTasksValueMenuPicker<Value> {
        self.init(
            label: label, value: options.first { $0.value == selection.wrappedValue }?.title ?? "",
            isDefault: isDefault
        ) {
            NewTasksValueMenuPicker(label: label, selection: selection, options: options)
        }
    }
}

struct NewTasksValueMenuPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [SettingsSelect<Value>.Option]

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

#if DEBUG
#Preview("New Tasks - Value menu, set and default") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.lg) {
            NewTasksValueMenu(label: "Effort", value: "High") { Button("High") {} }
            NewTasksValueMenu(label: "Mode", value: "Build", isDefault: true) { Button("Build") {} }
        }.padding(DS.Space.lg)
    }
}
#endif
