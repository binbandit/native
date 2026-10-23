import ACP
import SwiftUI
import TaskList

/// One decision at page size. The approval itself belongs to the shared transcript component.
struct HomeNextView: View {
    let agents: [HomeAgent<AgentDefinition.ID>]
    var isLoading = false

    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var order = HomeAskOrder.quickest
    @State private var current: SessionKey?
    @State private var visibleCount = DS.HomeNext.pageSize
    @State private var receipt: HomeNextReceipt?
    @State private var isAnswering = false
    @State private var safeAreaTop: CGFloat = 0

    var body: some View {
        let tasks = model.homeNextTasks
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
                            ask(task)
                                .id(task.approval?.id ?? task.id.id.rawValue)
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
        .animation(reduceMotion ? nil : .dsDisclosure, value: asks.map { $0.approval?.id ?? $0.id.id.rawValue })
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
                .onChange(of: order) { current = nil }
            }
        }
        .frame(minHeight: DS.HomeNext.headerHeight)
        .accessibilityAddTraits(.isHeader)
    }

    private func ask(_ task: HomeNextTask) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                StatusIndicator(status: task.status, size: DS.Size.navIcon)
                Text("\(task.agent) \(task.status == .failed ? "stopped" : "is waiting on you")")
                if let date = task.date {
                    Text("·")
                    DSMinuteTimeline { now in Text(DSFormat.compactAge(date, now: now)) }
                }
                Spacer(minLength: DS.Space.md)
                if let host = task.host {
                    Label(host, systemImage: "desktopcomputer")
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .font(.dsBody).foregroundStyle(.dsTextSecondary)
            title(task.title).padding(.top, DS.HomeNext.titleTop)
            if let call = task.approval {
                ToolCallView(call: call) { option in answer(option, task: task, call: call) }
                    .disabled(isAnswering)
            } else {
                Text(task.ask).font(DS.HomeNext.ledeFont).foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Task") { model.openHomeNextTask(task.id) }
                .buttonStyle(.ds(.ghost))
                .keyboardShortcut(.return, modifiers: .command)
                .padding(.top, DS.Space.lg)
        }
    }

    private func answer(_ option: PermissionOption, task: HomeNextTask, call: ToolCallState) {
        guard !isAnswering, let session = task.approvalSession,
            session.permissionRequests.contains(where: { $0.id == call.id && $0.permission == call.permission })
        else { return }
        isAnswering = true
        Task {
            await session.choose(option, forToolCall: call.id)
            receipt = HomeNextReceipt(
                task: task.id, title: task.title, command: call.shellCommand ?? call.title,
                rejected: option.isRejection, date: .now)
            isAnswering = false
        }
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
                HomeNextTaskRow(task: task, finished: finished) { model.openHomeNextTask(task.id) }
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
#Preview("Next - Quiet") { HomeNextPreviewFixtures.page(.quiet) }
#Preview("Next - First launch") { HomeNextPreviewFixtures.page(.first) }
#Preview("Next - Loading") { HomeNextPreviewFixtures.page(.loading) }
#Preview("Next - No tasks") { HomeNextPreviewFixtures.page(.empty) }
#Preview("Next - Recovery") { HomeNextPreviewFixtures.page(.recovery) }
#Preview("Next - Narrow and long title") { HomeNextPreviewFixtures.page(.narrow) }
#endif
