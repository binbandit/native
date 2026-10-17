import SwiftUI

// Gallery sections for status, the composer and general controls.

struct GalleryStatus: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading,
                spacing: DS.Space.sm
            ) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    HStack(spacing: DS.Space.sm) {
                        StatusIndicator(status: status)
                        Text(status.label)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(1)
                    }
                }
            }
            HStack(spacing: DS.Space.xxl) {
                ForEach(
                    [("typing", DotGridLoader.Pattern.typing), ("waiting", .waiting), ("settingUp", .settingUp)],
                    id: \.0
                ) { loader in
                    VStack(spacing: DS.Space.sm) {
                        DotGridLoader(pattern: loader.1)
                            .foregroundStyle(.dsTextPrimary)
                            .frame(width: 48, height: 48)
                        Text(loader.0).font(.dsCaption).foregroundStyle(.dsTextTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.sm) {
                        StatusDot()
                        Text("Unread").font(.dsCaption).foregroundStyle(.dsTextSecondary)
                    }
                    HStack(spacing: DS.Space.sm) {
                        DiffStatLabel(added: 1280, removed: 14)
                        DiffStatLabel(added: 9, removed: 3, isMuted: true)
                    }
                    CompactAgeText(date: .now.addingTimeInterval(-3600 * 5))
                }
            }
        }
    }
}

struct GalleryComposer: View {
    @State private var draft = ""
    @State private var isPlanMode = false
    @State private var isRunning = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            ComposerSurface {
                HStack(spacing: DS.Space.xs) {
                    ComposerChip("ComposerView.swift", systemImage: "doc.text") {}
                    ComposerChip("Selection: 12 lines", systemImage: "text.cursor") {}
                }
                .padding(DS.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .bottom, spacing: 0) {
                    TextField("What would you like to work on?", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.dsCallout)
                        .foregroundStyle(.dsTextPrimary)
                        .padding(DS.Composer.textInsets)
                    HStack(spacing: DS.Space.xs) {
                        if isRunning {
                            ComposerStopButton(isEscapeEnabled: false) { isRunning = false }
                        }
                        ComposerSendButton {}
                            .disabled(draft.isEmpty)
                    }
                    .padding(DS.Space.md)
                }
                .frame(minHeight: DS.Size.composerInputMinHeight)

                ComposerControlsBar {
                    Button("Attach", systemImage: "plus") {}
                        .labelStyle(.iconOnly)
                        .buttonStyle(.pill(isSquare: true))
                    PillMenu("Auto Model") {
                        Button("Claude Opus") {}
                        Button("GPT-5") {}
                    } accessory: {
                        EffortBars(level: 2)
                    }
                    PillMenu("Autonomy") {
                        Button("Low") {}
                        Button("High") {}
                    } accessory: {
                        EffortBars(level: 0, isMuted: true)
                    }
                    Button("Plan Mode") { isPlanMode.toggle() }
                        .buttonStyle(.pill(isOn: isPlanMode))
                    PillMenu("Connectors") {
                        Button("GitHub") {}
                    } accessory: {
                        StatusDot(color: .dsSuccess)
                    }
                    Button("?") {}
                        .buttonStyle(.pill(isSquare: true))
                        .help("Keyboard Shortcuts")
                } trailing: {
                    Button("Dictate", systemImage: "mic") {}
                        .labelStyle(.iconOnly)
                        .buttonStyle(.pill(isSquare: true))
                }
            }

            HStack(spacing: DS.Space.md) {
                Button("Plan Mode") {}.buttonStyle(.pill(isOn: true))
                Button("Disabled") {}.buttonStyle(.pill).disabled(true)
                ComposerChip("No remove button")
                ComposerSendButton {}
                ComposerSendButton {}.disabled(true)
                ComposerStopButton(isEscapeEnabled: false) {}
                Kbd("⇧⇥")
            }
        }
    }
}

struct GalleryControls: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                Button("Primary") {}.buttonStyle(.ds(.primary))
                Button("Secondary") {}.buttonStyle(.ds(.secondary))
                Button("Ghost", systemImage: "arrow.clockwise") {}.buttonStyle(.ds(.ghost))
                Button("Delete") {}.buttonStyle(.ds(.destructive))
                Button("Neutral") {}.buttonStyle(.ds(.neutral))
                Button("Disabled") {}.buttonStyle(.ds(.secondary)).disabled(true)
            }
            HStack(spacing: DS.Space.md) {
                Button("Small") {}.buttonStyle(.ds(.secondary, size: .small))
                Button("Medium") {}.buttonStyle(.ds(.secondary, size: .medium))
                Button("Large") {}.buttonStyle(.ds(.primary, size: .large))
                IconButton("Settings", systemImage: "gearshape") {}
                IconButton("Filter", systemImage: "line.3.horizontal.decrease", size: .medium) {}
                IconButton("Add", systemImage: "plus", size: .large, isActive: true) {}
            }
            HStack(spacing: DS.Space.md) {
                Badge("Beta")
                Badge("Running", tone: .accent, style: .soft)
                Badge("Merged", tone: .success, style: .soft)
                Badge("Failed", tone: .danger, style: .soft)
                Badge("New", tone: .accent, style: .mono)
                Badge("Pro", style: .mono)
                Kbd("⌘K")
                Kbd(KeyboardShortcut("n", modifiers: [.command, .shift]))
            }
            SectionHeader("Section header") {
                IconButton("Filter", systemImage: "line.3.horizontal.decrease") {}
                IconButton("Add", systemImage: "plus") {}
            }
            SeparatorLine()
            Card {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Card")
                        .font(.dsHeadline)
                        .foregroundStyle(.dsTextPrimary)
                    Text("Surface fill, 1pt separator outline, 8pt radius.")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            EmptyStateView(
                "No Sessions Yet", systemImage: "text.bubble",
                message: "Start one with ⌘N, or pick a project in the sidebar."
            ) {
                Button("New Session") {}.buttonStyle(.ds(.primary))
                Button("Open Folder…") {}.buttonStyle(.ds(.secondary))
            }
            .frame(height: 200)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
        }
    }
}
