import ACP
import SwiftUI
import TaskList

/// One decision at page size, using the same answer controls as the task.
struct HomeNextView: View {
    let agents: [HomeAgent<AgentDefinition.ID>]
    var isLoading = false

    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var order = HomeAskOrder.quickest
    @State private var current: SessionKey?
    @State private var currentRequest: HomeNextRequest.ID?
    @State private var visibleCount = DS.HomeNext.pageSize
    @State private var receipt: HomeNextReceipt?
    @State private var safeAreaTop: CGFloat = 0

    var body: some View {
        let tasks = model.homeNextTasks(retaining: currentRequest)
        let asks = order.sorted(tasks.filter(\.needsYou), retaining: current, id: \.id, kind: \.kind, date: \.date)
        let finished = tasks.filter {
            $0.finishedAt.map { Calendar.current.isDateInToday($0) } == true
        }.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.projects.all.isEmpty {
                    firstLaunch
                } else {
                    header(count: asks.count)
                    if let receipt {
                        HomeNextReceiptView(receipt: receipt) { model.openHomeNextTask(receipt.task) }
                            .padding(.top, DS.HomeNext.statusTop)
                    }
                    Group {
                        if let task = asks.first {
                            HomeNextAskView(task: task, onReceipt: { receipt = $0 }) {
                                model.openHomeNextTask(task.id)
                            }
                            .id(task.requestID)
                            .id(task.id)
                        } else {
                            quiet(finished: finished.count, working: tasks.filter { $0.status.isActive }.count)
                        }
                    }
                    .padding(.top, DS.HomeNext.askTop)
                    .padding(.bottom, DS.HomeNext.askBottom)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .offset(y: DS.HomeNext.rise).combined(with: .opacity), removal: .opacity))
                    SeparatorLine()
                    if asks.count > 1 {
                        rows(Array(asks.dropFirst()), title: "Up next", finished: false)
                    } else if asks.isEmpty, !finished.isEmpty {
                        rows(finished, title: "Finished today", finished: true)
                    }
                    HomeNextStatusLine(tasks: tasks)
                        .padding(.top, DS.HomeNext.statusTop)
                    if model.agentStartupFailure != nil {
                        HomeNextAgentReadiness(agents: agents) { settings.open(.agents) }
                            .padding(.top, DS.HomeNext.statusTop)
                    }
                }
            }
            .frame(maxWidth: DS.HomeNext.column, alignment: .leading)
            .padding(.horizontal, DS.Space.xxxl)
            .padding(.top, max(0, DS.HomeNext.top - safeAreaTop))
            .padding(.bottom, DS.Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear { model.setHomeNextVisible(true) }
        .onDisappear { model.setHomeNextVisible(false) }
        .scrollBounceBehavior(.basedOnSize)
        .background(.dsBackground)
        .safeAreaInset(edge: .bottom) {
            if !model.projects.all.isEmpty {
                Button {
                    Task { await model.newSession() }
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Text("New Task")
                        if let shortcut = CommandRegistry.shared.keyboardShortcut(for: .sessionNew) {
                            Kbd(shortcut)
                        }
                    }
                }
                .buttonStyle(.ds(.secondary))
                .padding(.bottom, DS.Space.xl)
            }
        }
        .dsToolbarBand(showsDivider: false)
        #if os(macOS)
        .toolbar(removing: .title)
        #endif
        .dropDestination(for: URL.self) { urls, _ -> Bool in model.dropHomeNextFolders(urls) }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.top
        } action: {
            safeAreaTop = $0
        }
        .onChange(of: asks.first?.id, initial: true) { _, id in current = id }
        .onChange(of: asks.first?.requestID, initial: true) { _, id in currentRequest = id }
        .animation(reduceMotion ? nil : .dsDisclosure, value: asks.map(\.id))
        .animation(reduceMotion ? nil : .dsDisclosure, value: asks.map(\.requestID))
        .animation(reduceMotion ? nil : .dsDisclosure, value: visibleCount)
        .animation(reduceMotion ? nil : .dsDisclosure, value: receipt?.date)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text("Needs you").font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
            Text(count == 0 ? "0" : "1 of \(count)")
                .font(.dsCallout).foregroundStyle(.dsTextTertiary).monospacedDigit()
                .accessibilityIdentifier("home-next-count")
            Spacer()
            if count > 0 {
                Menu {
                    Picker("Order asks", selection: $order) {
                        Text("Quickest first").tag(HomeAskOrder.quickest)
                        Text("Oldest first").tag(HomeAskOrder.oldest)
                    }
                } label: {
                    Text(order == .quickest ? "Quickest first" : "Oldest first")
                        .font(.dsBody).foregroundStyle(.dsTextSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .frame(minHeight: DS.HomeNext.headerHeight)
        .accessibilityAddTraits(.isHeader)
    }

    private func quiet(finished: Int, working: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                isLoading
                    ? "Checking your projects"
                    : receipt.map { "Your last answer was at \($0.date.formatted(date: .omitted, time: .shortened))" }
                        ?? "Nothing needs you now"
            )
            .font(.dsBody).foregroundStyle(.dsTextTertiary)
            title(isLoading ? "Finding your tasks…" : "You’re clear.").padding(.top, DS.HomeNext.titleTop)
            Text(
                isLoading
                    ? "Your agents are checking for saved tasks. Asks will appear here as they arrive."
                    : finished > 0
                        ? "\(finished) \(finished == 1 ? "task finished" : "tasks finished") today."
                        : working > 0
                            ? "Your agents are working. Their next ask will appear here."
                            : "Start a task. When an agent needs you, it shows up here."
            )
            .font(DS.HomeNext.ledeFont).tracking(DS.HomeNext.ledeTracking)
            .foregroundStyle(.dsTextSecondary)
        }
    }

    private func rows(_ tasks: [HomeNextTask], title: String, finished: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text(title).font(.dsBodyMedium).foregroundStyle(.dsTextSecondary)
                if finished { Text("\(tasks.count)").font(.dsBody).foregroundStyle(.dsTextTertiary) }
            }
            .padding(.bottom, DS.Space.md)
            .accessibilityAddTraits(.isHeader)
            ForEach(tasks.prefix(visibleCount)) { task in
                HomeNextTaskRow(task: task, finished: finished) { model.peekHomeNextTask(task) }
                    .taskPeekAnchor(task.id)
                    .contextMenu {
                        Button("Peek") { model.peekHomeNextTask(task) }
                        Button("Open Task") { model.openHomeNextTask(task.id) }
                    }
            }
            if tasks.count > visibleCount {
                Button("Show \(min(DS.HomeNext.pageSize, tasks.count - visibleCount)) more") {
                    visibleCount += DS.HomeNext.pageSize
                }
                .buttonStyle(.plain).font(.dsBody).foregroundStyle(.dsTextPrimary)
                .dsHitTarget(DS.Size.controlXS)
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                .padding(.top, DS.Space.md)
            }
        }
        .padding(.top, DS.HomeNext.sectionTop)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(DS.HomeNext.titleFont).tracking(DS.HomeNext.titleTracking)
            .foregroundStyle(.dsTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, DS.HomeNext.askBottom)
            .accessibilityAddTraits(.isHeader)
    }

    private var firstLaunch: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Add a project")
            Text("A folder with code in it. Your agents work there, and when one needs you, it shows up here.")
                .font(DS.HomeNext.ledeFont).tracking(DS.HomeNext.ledeTracking)
                .foregroundStyle(.dsTextSecondary).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.HomeNext.statusTop) {
                    openFolder; dropHint
                }
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    openFolder; dropHint
                }
            }
            .padding(.top, DS.HomeNext.sectionTop)
            HomeNextAgentReadiness(agents: agents) { settings.open(.agents) }
                .padding(.top, DS.HomeNext.askTop)
        }
        .padding(.top, DS.HomeNext.headerHeight + DS.HomeNext.askTop)
    }

    private var openFolder: some View {
        Button(action: model.openHomeNextFolder) {
            HStack(spacing: DS.Space.md) {
                Text("Open Folder…")
                if let shortcut = CommandRegistry.shared.keyboardShortcut(for: .projectOpen) { Kbd(shortcut) }
            }
        }
        .buttonStyle(.ds(.primary))
    }

    private var dropHint: some View {
        Text("or drop a folder here").font(.dsBody).foregroundStyle(.dsTextTertiary)
    }
}

#if DEBUG
#Preview("Next - Busy") { HomeNextPreviewFixtures.page(.busy) }
#Preview("Next - Every module off") { HomeNextPreviewFixtures.page(.calm) }
#Preview("Next - Managed") { HomeNextPreviewFixtures.page(.managed) }
#Preview("Next - Quiet") { HomeNextPreviewFixtures.page(.quiet) }
#Preview("Next - First launch") { HomeNextPreviewFixtures.page(.first) }
#Preview("Next - Loading") { HomeNextPreviewFixtures.page(.loading) }
#Preview("Next - No tasks") { HomeNextPreviewFixtures.page(.empty) }
#Preview("Next - Recovery") { HomeNextPreviewFixtures.page(.recovery) }
#Preview("Next - Narrow and long title") { HomeNextPreviewFixtures.page(.narrow) }
#endif
