import SwiftUI

/// A receipt, in precedence order, shared by editable and policy-limited starting values.
struct NewTasksSourceStack: View {
    let receipt: NewTasksSettingReceipt

    /// An organization that decides nothing here isn't listed: "Not set" would read as managed.
    private var layers: [NewTasksSettingReceipt.Layer] {
        receipt.layers.filter { !$0.isOrganization || $0.value != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                Text(receipt.title).font(.dsBodyMedium).foregroundStyle(.dsTextPrimary)
                Text(receipt.context).font(DS.Settings.caption).foregroundStyle(.dsTextTertiary)
            }
            .padding(DS.Space.lg)
            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                SeparatorLine().padding(.horizontal, DS.Space.lg)
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                    Label(layer.name, systemImage: layer.symbol)
                        .frame(width: DS.Settings.sourceColumnWidth, alignment: .leading)
                    Text(layer.value ?? "Not set")
                        .foregroundStyle(layer.wins ? .dsTextPrimary : .dsTextTertiary)
                        .strikethrough(layer.overridden)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if layer.isOrganization && layer.wins {
                        Image(systemName: "lock").foregroundStyle(.dsTextTertiary)
                            .accessibilityLabel("Decided by \(layer.name)")
                    }
                }
                .font(DS.Settings.caption)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.md)
                .accessibilityElement(children: .combine)
                .accessibilityValue(layer.wins ? "Used" : layer.overridden ? "Overridden" : "")
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                Text("Starts with").foregroundStyle(.dsTextSecondary)
                Text(receipt.value).foregroundStyle(.dsTextPrimary)
                Spacer(minLength: 0)
                if let reason = receipt.reason {
                    Text(reason).font(DS.Settings.caption).foregroundStyle(.dsTextTertiary)
                }
            }
            .font(DS.Settings.groupTitle)
            .padding(DS.Space.md)
            .background(.dsSelected, in: .rect(cornerRadius: DS.Radius.control))
            .padding(DS.Space.lg)
            Text(receipt.help ?? receipt.note)
                .font(DS.Settings.caption)
                .foregroundStyle(.dsTextTertiary)
                .padding([.horizontal, .bottom], DS.Space.lg)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: DS.Settings.sourceStackWidth)
        .dsPopoverBackground()
    }
}

#if DEBUG
#Preview("New Tasks - Source stack, inherited and locked") {
    DSPreviewPair {
        VStack {
            NewTasksSourceStack(receipt: NewTasksPreviewFixtures.receipt(managed: false))
            NewTasksSourceStack(receipt: NewTasksPreviewFixtures.receipt(managed: true))
        }
    }
}
#endif
