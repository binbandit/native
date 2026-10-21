import SwiftUI

/// The sidebar over a busy backdrop, so the translucent material shows.
struct GallerySidebar: View {
    @State private var nativeExpanded = true
    @State private var otherExpanded = true
    @State private var selection = "tokens"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: DS.Size.sidebarWidth)
                .dsSidebarBackground(blending: .withinWindow)
                .overlay(alignment: .trailing) { SeparatorLine(axis: .vertical) }
            Spacer(minLength: 0)
        }
        .frame(height: 720)
        .background { GalleryBackdrop() }
        .clipShape(.rect(cornerRadius: DS.Radius.card))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.xs) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(.dsTextQuaternary).frame(width: 12, height: 12)
                    }
                }
                .padding(.leading, DS.Space.md)
                .padding(.trailing, DS.Space.lg)
                SidebarCollapseButton(isExpanded: true) {}
                UpdateButton(version: "1.4.0") {}
                    .padding(.horizontal, DS.Space.xs)
                HistoryNavigationButtons(canGoBack: true, canGoForward: false, onBack: {}, onForward: {})
            }
            .frame(height: DS.Window.headerHeight)

            VStack(spacing: 0) {
                SidebarNavItem("New Task", systemImage: "plus", shortcut: "⌘N") {
                } accessory: {
                    SidebarRowMenu(label: "Choose an Agent") {
                        Button("Claude Code") {}
                        Button("Codex") {}
                    }
                }
                SidebarNavItem("Mission Control", systemImage: "flag") {}
                SidebarNavItem("Automations", systemImage: "sparkle") {}
                SidebarNavItem("Search", systemImage: "magnifyingglass", shortcut: "⌘K") {}
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.lg)

            UsageMeter(title: "Usage", fraction: 0.42, detail: "Resets in 2h")
                .padding(.horizontal, DS.Space.lg + DS.Space.sm)
                .padding(.vertical, DS.Space.lg)

            SectionHeader("Projects") {
                IconButton("Filter", systemImage: "line.3.horizontal.decrease") {}
                IconButton("Add Project", systemImage: "folder.badge.plus") {}
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.md)

            VStack(alignment: .leading, spacing: 0) {
                ProjectGroup(
                    name: "native", isExpanded: $nativeExpanded, taskCount: GalleryFixtures.tasks.count, onNewTask: {}
                ) {
                    Button("Reveal in Finder") {}
                    Divider()
                    Button("Remove Project", role: .destructive) {}
                } content: {
                    ForEach(GalleryFixtures.tasks) { task in
                        TaskRow(task, isSelected: selection == task.id) { selection = task.id }
                    }
                }
                ProjectGroup(
                    name: "companion", icon: .symbol("folder"), isExpanded: $otherExpanded, taskCount: 2, onNewTask: {}
                ) {
                    TaskRow(
                        title: "Agent icon and context",
                        status: .working,
                        isSelected: selection == "slots",
                        date: .now.addingTimeInterval(-600),
                        leadingSymbol: "sparkle",
                        accessory: ContextUsageRing(fraction: 0.78),
                        action: { selection = "slots" }
                    )
                    TaskRow(
                        title: "Context nearly full",
                        status: .idle,
                        isSelected: selection == "full",
                        leadingSymbol: "chevron.left.forwardslash.chevron.right",
                        accessory: ContextUsageRing(fraction: 0.96),
                        action: { selection = "full" }
                    )
                }
            }
            .padding(.horizontal, DS.Space.sm)
            Spacer(minLength: 0)
        }
    }
}

/// Colorful shapes for the translucent sidebar to blur.
private struct GalleryBackdrop: View {
    var body: some View {
        ZStack {
            Color.dsBackground
            Circle().fill(.orange).frame(width: 220).offset(x: -120, y: -170)
            Circle().fill(.blue).frame(width: 180).offset(x: 40, y: 40)
            RoundedRectangle(cornerRadius: 30).fill(.pink).frame(width: 140, height: 240).rotationEffect(.degrees(20))
                .offset(x: -60, y: 200)
            Text("Native")
                .font(.ds(64, weight: .bold))
                .foregroundStyle(.green)
                .rotationEffect(.degrees(-12))
                .offset(x: 120, y: -40)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Gallery - Sidebar") {
    DSPreviewPair {
        GallerySidebar()
    }
}
#endif
