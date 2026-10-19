import ProjectIcons
import SwiftUI
import UniformTypeIdentifiers

/// Picks what leads a project in the sidebar: an icon file found in the project (its favicon, logo
/// or app icon, SVG or bitmap), an emoji, a symbol, an image file, or automatic (the first icon
/// found, else its initial). Every change can be undone.
struct ProjectIconPicker: View {
    let project: Project
    let store: ProjectIconStore

    private enum Tab: String, CaseIterable, Identifiable {
        case project = "Project"
        case emoji = "Emoji"
        case symbol = "Symbols"
        case image = "Image"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var tab: Tab
    @State private var typedEmoji = ""
    @State private var isImporting = false
    @State private var importFailure: String?
    /// Nil until the project's been looked through.
    @State private var found: [ProjectIconResolver.FoundIcon]?

    init(project: Project, store: ProjectIconStore) {
        self.project = project
        self.store = store
        _tab = State(initialValue: Self.tab(showing: store.choice(for: project.id)))
    }

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

    /// The found icons' cells.
    private static let foundSide: CGFloat = 24

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
            case .project: projectTab
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
                    .help("The first icon found in the project, or its initial")
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 300)
        .task { found = await store.foundIcons(in: project) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.svg, .image]) { result in
            guard case .success(let url) = result else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importFailure = "Native couldn't read that file."
                return
            }
            let isSVG = UTType(filenameExtension: url.pathExtension).map { $0.conforms(to: .svg) }
            do throws(ProjectIconRejection) {
                try store.setCustomImage(data, isSVG: isSVG, for: project, undoManager: undoManager)
                dismiss()
            } catch {
                importFailure = error.message
            }
        }
    }

    @ViewBuilder
    private var projectTab: some View {
        if let found, !found.isEmpty {
            LazyVGrid(columns: Self.columns, spacing: DS.Space.xs) {
                ForEach(found) { icon in
                    cell(isSelected: isCurrent(icon), label: icon.path) {
                        store.choose(icon, for: project, undoManager: undoManager)
                        dismiss()
                    } content: {
                        if let image = icon.artwork.image(side: Self.foundSide) {
                            image
                                .foregroundStyle(.dsTextSecondary)
                                .frame(width: Self.foundSide, height: Self.foundSide)
                                .clipShape(.rect(cornerRadius: DS.Radius.control, style: .continuous))
                        }
                    }
                    .help(icon.path)
                }
            }
        } else if found == nil {
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .waiting)
                Text("Looking through \(project.name)…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
            .frame(minHeight: DS.Size.controlMD)
        } else {
            Text(
                "No icon found in the project. Native looks for favicon.svg, icon.svg, logo.svg, apple-touch-icon.png, favicon.ico and app icons. Choose an image instead."
            )
            .font(.dsBody)
            .foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
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
            Text("An SVG stays sharp at every size. A bitmap (PNG, JPEG, ICO) is kept as a small copy.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose Image…") { isImporting = true }
                .buttonStyle(.ds(.secondary))
            if let importFailure {
                Text(importFailure)
                    .font(.dsBody)
                    .foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.xs), count: 6)

    private func grid<Cell: View>(
        _ values: [String],
        @ViewBuilder cell content: @escaping (String) -> Cell,
        choose makeChoice: @escaping (String) -> ProjectIconChoice
    ) -> some View {
        LazyVGrid(columns: Self.columns, spacing: DS.Space.xs) {
            ForEach(values, id: \.self) { value in
                let choice = makeChoice(value)
                cell(isSelected: store.choice(for: project.id) == choice, label: value) {
                    choose(choice)
                } content: {
                    content(value)
                }
            }
        }
    }

    private func cell<Content: View>(
        isSelected: Bool, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, minHeight: max(DS.Size.controlMD, DS.Size.minimumHitTarget))
                .background(
                    isSelected ? Color.dsSelected : .clear,
                    in: .rect(cornerRadius: DS.Radius.control, style: .continuous)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The file the project's icon comes from now: the one chosen, or the one automatic found.
    private func isCurrent(_ icon: ProjectIconResolver.FoundIcon) -> Bool {
        switch store.choice(for: project.id) {
        case .file(let path): path == icon.path
        case .automatic: store.isDetected(icon, in: project)
        default: false
        }
    }

    /// The tab the current choice is on, so the picker opens where it was made.
    private static func tab(showing choice: ProjectIconChoice) -> Tab {
        switch choice {
        case .automatic, .file, .initial: .project
        case .emoji: .emoji
        case .symbol: .symbol
        case .image: .image
        }
    }

    /// Emoji drawn as emoji: presentation-default ones, or text symbols with the emoji selector.
    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    }

    private func choose(_ choice: ProjectIconChoice) {
        store.setChoice(choice, for: project, undoManager: undoManager)
        dismiss()
    }
}
