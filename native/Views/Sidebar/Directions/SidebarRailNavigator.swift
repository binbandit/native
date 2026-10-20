#if DEBUG
import SwiftUI

/// The rail's navigator: a filter field, then every task (or one project's) with the ⌘ key that
/// opens it, and the keys at the foot. ↑ and ↓ move the selection while it has focus, as in
/// today's sidebar.
struct SidebarRailNavigator: View {
    @Environment(AppModel.self) private var model
    @Binding var focusedProject: Project.ID?

    @State private var query = ""
    @FocusState private var isListFocused: Bool

    var body: some View {
        // ⌘1 – ⌘9 go to the Nth task in the sidebar's order.
        let numbers = Dictionary(
            model.sessionList.prefix(9).enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { first, _ in first })
        let projects = model.projects.all.filter { focusedProject == nil || $0.id == focusedProject }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                SearchField("Filter tasks", text: $query)
                if focusedProject != nil {
                    IconButton("Show Every Project", systemImage: "square.stack") {
                        withAnimation(.dsQuick) { focusedProject = nil }
                    }
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.top, DS.Space.sm)
            .padding(.bottom, DS.Space.xs)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.xxs) {
                    ForEach(projects, id: \.id) { project in
                        let tasks = model.sidebarDesignTasks(in: project.id).filter(matches)
                        SidebarRailNavigatorHeader(project: project, count: tasks.count)
                        if tasks.isEmpty, query.isEmpty {
                            SidebarDesignStartRow(title: "No tasks yet. Start one") {
                                Task { await model.newSession(in: project.id) }
                            }
                        }
                        ForEach(tasks) { task in
                            SidebarDesignRow(
                                task: task, detail: task.isYourMove ? task.detail : nil,
                                detailTone: SidebarDesignTone(task), verticalPadding: DS.Space.sm
                            ) {
                                SidebarDesignMark(task: task)
                            } trailing: {
                                if let device = task.device {
                                    SidebarDesignDevice(name: device)
                                }
                                if let number = numbers[task.id] {
                                    Kbd("⌘\(number)")
                                } else if let date = task.date {
                                    CompactAgeText(date: date)
                                }
                            }
                        }
                    }
                    if !query.isEmpty,
                        projects.allSatisfy({ model.sidebarDesignTasks(in: $0.id).filter(matches).isEmpty })
                    {
                        Text("No task matches “\(query)”. Search (⇧⌘F) looks inside transcripts too.")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                            .padding(DS.Space.sm)
                    }
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.bottom, DS.Space.md)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) {
                model.selectSession(offset: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.selectSession(offset: 1)
                return .handled
            }

            SidebarRailKeys()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func matches(_ task: SidebarDesignTask) -> Bool {
        query.isEmpty || task.title.localizedStandardContains(query)
    }
}

/// A project's name over its tasks in the navigator.
private struct SidebarRailNavigatorHeader: View {
    let project: Project
    let count: Int

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(project.name)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
            Text("\(count)")
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.xxs)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The keys the navigator answers, at its foot.
private struct SidebarRailKeys: View {
    var body: some View {
        HStack(spacing: DS.Space.md) {
            key("↑↓", "move")
            key("↩", "open")
            key("⌃⌘S", "hide")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.chromeBar)
        .overlay(alignment: .top) {
            SeparatorLine()
        }
    }

    private func key(_ keys: String, _ action: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Kbd(keys)
            Text(action)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }
}
#endif
