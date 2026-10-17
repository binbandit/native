import SwiftUI
import UniformTypeIdentifiers

/// Picks what leads a project in the sidebar (Conductor's repository icon picker): an emoji, a
/// symbol, an image file, or automatic (the icon found in the project, else its initial).
struct ProjectIconPicker: View {
    let project: Project
    let store: ProjectIconStore

    private enum Tab: String, CaseIterable, Identifiable {
        case emoji = "Emoji"
        case symbol = "Symbols"
        case image = "Image"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.emoji
    @State private var typedEmoji = ""
    @State private var isImporting = false
    @State private var importFailed = false

    private static let emoji = [
        "🚀", "⚡️", "🔥", "✨", "🌱", "🌊", "🌙", "☀️", "🧪", "🧠", "🤖", "🛠️",
        "📦", "📚", "📝", "🎨", "🎮", "🎧", "📱", "💻", "🖥️", "⌚️", "🌐", "🔒",
        "🧩", "🪐", "🐙", "🦊", "🐝", "🦄", "🍎", "🍋", "🍕", "☕️", "🏠", "🏁",
    ]

    private static let symbols = [
        "folder", "shippingbox", "hammer", "wrench.and.screwdriver", "terminal",
        "chevron.left.forwardslash.chevron.right",
        "cpu", "server.rack", "globe", "network", "cloud", "lock",
        "doc.text", "book", "graduationcap", "paintbrush", "photo", "film",
        "music.note", "gamecontroller", "iphone", "laptopcomputer", "applewatch", "car",
        "leaf", "flame", "bolt", "sparkles", "star", "heart",
        "flag", "cart", "creditcard", "chart.bar", "map", "person.2",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                ProjectAvatar(name: project.name, icon: store.icon(for: project))
                Text(project.name)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
            }
            Picker("Icon kind", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .emoji: emojiTab
            case .symbol: symbolTab
            case .image: imageTab
            }

            Divider()
            HStack {
                Button("Use Initial") { choose(.initial) }
                    .buttonStyle(.ds(.ghost))
                Spacer()
                Button("Automatic") { choose(.automatic) }
                    .buttonStyle(.ds(.secondary))
                    .help("The icon found in the project, or its initial")
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 300)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), store.setCustomImage(data, for: project.id) {
                dismiss()
            } else {
                importFailed = true
            }
        }
    }

    private var emojiTab: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            grid(Self.emoji) { emoji in
                Text(emoji).font(.dsTitle3)
            } choose: {
                .emoji($0)
            }
            TextField("Or type any emoji", text: $typedEmoji)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let first = typedEmoji.first, Self.isEmoji(first) {
                        choose(.emoji(String(first)))
                    }
                }
        }
    }

    private var symbolTab: some View {
        grid(Self.symbols) { name in
            Image(systemName: name)
                .font(.dsCallout)
                .foregroundStyle(.dsTextSecondary)
        } choose: {
            .symbol($0)
        }
    }

    private var imageTab: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let detected = store.detectedImage(for: project.id) {
                Button {
                    choose(.automatic)
                } label: {
                    HStack(spacing: DS.Space.md) {
                        detected.resizable().frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                        Text("Use the icon found in the project")
                            .font(.dsBody)
                    }
                }
                .buttonStyle(.ds(.ghost))
            } else {
                Text("No icon found in the project. Native looks for a favicon, logo or app icon.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Choose Image…") { isImporting = true }
                .buttonStyle(.ds(.secondary))
            if importFailed {
                Text("That file isn't an image Native can read. Try a PNG, JPEG or ICO.")
                    .font(.dsBody)
                    .foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func grid<Cell: View>(
        _ values: [String],
        @ViewBuilder cell: @escaping (String) -> Cell,
        choose makeChoice: @escaping (String) -> ProjectIconChoice
    ) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.xs), count: 6), spacing: DS.Space.xs
        ) {
            ForEach(values, id: \.self) { value in
                let choice = makeChoice(value)
                Button {
                    choose(choice)
                } label: {
                    cell(value)
                        .frame(maxWidth: .infinity, minHeight: max(DS.Size.controlMD, DS.Size.minimumHitTarget))
                        .background(
                            store.choice(for: project.id) == choice ? Color.dsSelected : .clear,
                            in: .rect(cornerRadius: DS.Radius.control, style: .continuous)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value)
            }
        }
    }

    /// Emoji drawn as emoji: presentation-default ones, or text symbols with the emoji selector.
    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    }

    private func choose(_ choice: ProjectIconChoice) {
        store.setChoice(choice, for: project.id)
        dismiss()
    }
}
