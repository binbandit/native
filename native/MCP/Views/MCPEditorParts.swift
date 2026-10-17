import SwiftUI

extension View {
    /// Conductor's input: an outlined 32pt field on the background, like `SettingsSelect`.
    func mcpFieldStyle() -> some View {
        modifier(MCPFieldStyle())
    }
}

private struct MCPFieldStyle: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        content
            .textFieldStyle(.plain)
            .settingsText(.body)
            .foregroundStyle(.dsTextPrimary)
            .focused($isFocused)
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: SettingsMetrics.controlHeight)
            .background(.dsBackground, in: shape)
            .overlay { shape.strokeBorder(isFocused ? Color.dsBorderStrong : .dsBorder, lineWidth: 1) }
    }
}

/// Name-value pairs whose values are secrets: hidden unless shown, kept in the Keychain.
struct MCPSecretList: View {
    let title: String
    let addTitle: String
    let namePrompt: String
    @Binding var pairs: [MCPServerDraft.Pair]

    @State private var revealed: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text(title)
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Spacer()
                Button(addTitle, systemImage: "plus") { pairs.append(MCPServerDraft.Pair()) }
                    .buttonStyle(.ds(.ghost, size: .medium))
            }
            if pairs.isEmpty {
                Text("None.")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
            }
            ForEach($pairs) { $pair in
                HStack(spacing: DS.Space.md) {
                    TextField("Name", text: $pair.name, prompt: Text(namePrompt))
                        .font(.dsMono)
                        .mcpFieldStyle()
                        .frame(width: 180)
                    Group {
                        if revealed.contains(pair.id) {
                            TextField("Value", text: $pair.value)
                        } else {
                            SecureField("Value", text: $pair.value)
                        }
                    }
                    .font(.dsMono)
                    .mcpFieldStyle()
                    IconButton(
                        revealed.contains(pair.id) ? "Hide Value" : "Show Value",
                        systemImage: revealed.contains(pair.id) ? "eye.slash" : "eye", size: .medium
                    ) {
                        if !revealed.insert(pair.id).inserted { revealed.remove(pair.id) }
                    }
                    IconButton(
                        "Remove \(pair.name.isEmpty ? "Row" : pair.name)", systemImage: "minus.circle", size: .medium
                    ) {
                        pairs.removeAll { $0.id == pair.id }
                    }
                }
            }
        }
    }
}

/// Everything, or a chosen few: an "All" switch and, when it's off, a switch per option.
struct MCPChoiceList: View {
    let title: String
    let allTitle: String
    @Binding var isAll: Bool
    @Binding var chosen: Set<String>
    let options: [(id: String, name: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text(title)
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Spacer()
                Text(allTitle)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
                SettingsSwitch(allTitle, isOn: $isAll)
            }
            if !isAll {
                if options.isEmpty {
                    Text("None to choose from yet.")
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextTertiary)
                }
                ForEach(options, id: \.id) { option in
                    HStack {
                        Text(option.name)
                            .settingsText(.body)
                            .foregroundStyle(.dsTextPrimary)
                        Spacer()
                        SettingsSwitch(
                            option.name,
                            isOn: Binding(
                                get: { chosen.contains(option.id) },
                                set: { if $0 { chosen.insert(option.id) } else { chosen.remove(option.id) } }
                            ))
                    }
                    .padding(.leading, DS.Space.xl)
                }
            }
        }
    }
}
