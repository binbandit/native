import ACP
import GitHub
import SwiftUI
import TaskList

/// One decision at page size, using the same answer controls as the task.
struct HomeNextView: View {
    let agents: [HomeAgent<AgentDefinition.ID>]
    var isLoading = false

    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    @FocusedValue(\.showsPullRequests) private var showsPullRequests
    @AppStorage(HomeNextSummary.reviews.storageKey) private var showsReviews = false
    @AppStorage(HomeNextSummary.usageLimits.storageKey) private var showsLimits = false
    @AppStorage(HomeNextSummary.away.storageKey) private var showsAway = false
    @State private var order = HomeAskOrder.quickest
    @State private var current: SessionKey?
    @State private var currentRequest: HomeNextRequest.ID?
    @State private var visibleCount = DS.HomeNext.pageSize
    @State private var receipt: HomeNextReceipt?
    @State private var safeAreaTop: CGFloat = 0

    var body: some View {
        let tasks = model.homeNextTasks(retaining: currentRequest)
        let limits = showsLimits ? model.homeNextLimits : []
        // A task a limit stopped is told once, by its limit's row, rather than as a failure to retry.
        let limited = Set(limits.flatMap(\.tasks))
        let asks = order.sorted(
            tasks.filter { $0.needsYou && !($0.status == .failed && limited.contains($0.id)) },
            retaining: current, id: \.id, kind: \.kind, date: \.date)
        let reviews = showsReviews ? HomeNextReviews(gitHub?.inbox?.reviewRequested ?? []) : nil
        let finished = tasks.filter {
            $0.finishedAt.map { Calendar.current.isDateInToday($0) } == true
        }.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.projects.all.isEmpty {
                    firstLaunch
                } else {
                    header(asks: asks.count, total: asks.count + (reviews == nil ? 0 : 1))
                    if let receipt {
                        HomeNextReceiptView(receipt: receipt) {
                            model.openHomeNextTask(receipt.starting?.openedSession ?? receipt.task)
                        }
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
                    if asks.count > 1 || reviews != nil || !limits.isEmpty {
                        upNext(Array(asks.dropFirst()), reviews: reviews, limits: limits)
                    }
                    if asks.isEmpty, !finished.isEmpty {
                        rows(finished, title: "Finished today", finished: true)
                    }
                    HomeNextStatusLine(tasks: tasks, away: showsAway ? awaySentence : nil)
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
        .preference(
            key: HomePresentedTaskAskKey.self,
            value: Set(
                asks.prefix(visibleCount + 1).compactMap { task -> HomePresentedTaskNeed? in
                    if let id = task.request?.taskPeekID(task: task.id) { return .request(id) }
                    return task.status == .failed ? .failure(task.id) : nil
                })
        )
        .onAppear { model.setHomeNextVisible(true) }
        .onDisappear { model.setHomeNextVisible(false) }
        .scrollBounceBehavior(.basedOnSize)
        .background(.dsBackground)
        .safeAreaInset(edge: .bottom) {
            if !model.projects.all.isEmpty {
                HomeNextStartField { task in
                    receipt = HomeNextReceipt(
                        task: task.id, title: model.projects.project(task.project)?.name ?? "the project",
                        action: "Started a \(task.agent.displayName) task", date: .now, starting: task)
                }
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

    /// While an ask is on the page, "1 of 5"; otherwise how many rows still want the user.
    private func header(asks: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text("Needs you").font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
            Text(asks == 0 ? "\(total)" : "1 of \(total)")
                .font(.dsCallout).foregroundStyle(.dsTextTertiary).monospacedDigit()
                .accessibilityIdentifier("home-next-count")
            Spacer()
            if asks > 0 {
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
                    : receipt.flatMap { $0.starting == nil ? $0 : nil }.map {
                        "Your last answer was at \($0.date.formatted(date: .omitted, time: .shortened))"
                    } ?? "Nothing needs you now"
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

    /// The asks after the current one, then the summaries the user chose to add.
    private func upNext(_ asks: [HomeNextTask], reviews: HomeNextReviews?, limits: [HomeNextLimit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            rows(asks, title: "Up next", finished: false)
            if let reviews {
                HomeNextRow(
                    status: .needsInput, title: reviews.title, detail: reviews.detail, date: reviews.since,
                    describesStatus: false
                ) { openReviews(reviews) }
                .accessibilityHint("Opens your review requests")
            }
            ForEach(limits) { limit in
                let row = HomeNextRow(
                    status: .limited, title: limit.title, detail: limit.detail, date: limit.since,
                    describesStatus: false
                ) {
                    if limit.tasks.isEmpty { settings.open(.usage) } else { model.peekHomeNextLimit(limit) }
                }
                if let task = limit.tasks.first {
                    row.taskPeekAnchor(task).accessibilityHint("Opens Peek without leaving Home")
                } else {
                    row.accessibilityHint("Opens Usage settings")
                }
            }
        }
    }

    /// One request opens its page; several open the list, filtered to them.
    private func openReviews(_ reviews: HomeNextReviews) {
        guard let gitHub else { return }
        if reviews.pullRequests.count > 1, let showsPullRequests {
            gitHub.closePullRequestPage()
            gitHub.filter.scope = .reviewRequested
            showsPullRequests.wrappedValue = true
        } else if let first = reviews.pullRequests.first {
            gitHub.open(first)
        }
    }

    private var awaySentence: String? {
        guard let away = model.homeNext.away, away.isNews, Calendar.current.isDateInToday(away.end) else { return nil }
        return away.sentence
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
#Preview("Next - Every summary on") { HomeNextPreviewFixtures.page(.summaries) }
#Preview("Next - Draft in the start field") { HomeNextPreviewFixtures.page(.typed) }
#endif
