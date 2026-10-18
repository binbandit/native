import ACP
import Foundation
import Observation

/// Tracks each provider's usage limit, tells the user when one is close or reached, and picks the
/// sessions it stopped back up at the reset if the user asks. Limits belong to the account behind
/// an agent, so they're kept per agent; sessions only record what to send when they resume.
@Observable
final class UsageLimits {
    /// How long past a reset a resume waits: providers round reset times to the minute.
    static let resetMargin: TimeInterval = 90
    /// How long a structured "rejected" status explains a failed turn that doesn't name a limit.
    static let statusFreshness: TimeInterval = 120
    /// A limit whose reset was never reported is forgotten after this long.
    static let unknownResetExpiry: TimeInterval = 24 * 3600
    /// Gives the failed turn that follows a status change a moment to register, so the alert can
    /// name the session it stopped.
    static let alertDelay: Duration = .milliseconds(600)
    /// How often a resume retries while its session can't be reached (its agent is still starting).
    static let retryInterval: TimeInterval = 30
    static let maxResumeAttempts = 20

    private(set) var providers: [AgentDefinition.ID: ProviderLimit] = [:]
    private(set) var sessions: [UsageSessionRef.ID: LimitedSession] = [:]

    /// Resumes wait for this; setting it runs any that came due before it was there.
    @ObservationIgnored weak var host: (any UsageLimitsHost)? {
        didSet {
            gated = [:]
            processDue()
        }
    }

    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private let store: any UsageLimitsStore
    @ObservationIgnored private let alerts: any LimitAlerting
    @ObservationIgnored private let timer = LimitTimer()
    @ObservationIgnored private var pendingAlerts: [AgentDefinition.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var resumeAttempts: [UsageSessionRef.ID: Int] = [:]
    @ObservationIgnored private var isProcessing = false
    /// Sessions picked back up at a reset, until a turn of theirs ends normally. One that hits the
    /// limit again waits for the next reset on its own rather than asking again.
    @ObservationIgnored private var resumed: Set<UsageSessionRef.ID> = []
    /// What the host's send gate was last told, per agent.
    @ObservationIgnored private var gated: [AgentDefinition.ID: String] = [:]

    init(store: any UsageLimitsStore, alerts: any LimitAlerting, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.alerts = alerts
        self.now = now
        let snapshot = store.load()
        providers = Dictionary(snapshot.providers.map { ($0.agent, $0) }) { $1 }
        sessions = Dictionary(snapshot.sessions.map { ($0.id, $0) }) { $1 }
        alerts.onAction = { [weak self] action in self?.perform(action) }
        // Resumes that came due while Native wasn't running fire as soon as there's a host.
        processDue()
    }

    // MARK: - What the agents report

    /// A provider's structured status, such as Claude Code's `_claude/rateLimit`.
    func record(_ info: RateLimitInfo, agent: AgentDefinition.ID, agentName: String) {
        if info.isBlocking {
            let until = info.blockedUntil
            // A late report about a reset that already passed says nothing about now.
            if let until, until <= now() { return }
            let current = providers[agent]
            report(
                agent, agentName: agentName, status: .reached, window: info.window, resetsAt: until,
                utilization: info.utilization, message: current?.status == .reached ? current?.message : nil)
        } else if info.isWarning {
            if let current = providers[agent], current.status == .reached, isInForce(current) { return }
            report(
                agent, agentName: agentName, status: .warning, window: info.window, resetsAt: info.resetsAt,
                utilization: info.utilization, message: nil)
        } else if info.effectiveStatus == .allowed {
            clearLimit(of: agent, resumingScheduled: true)
            processDue()
        }
    }

    /// A turn that failed. Returns whether a usage limit stopped it; if so, the session waits for
    /// the reset with what it should send then.
    /// `target` is nil for sessions that can't be prompted, like subagents: their failure still
    /// tells about the provider.
    @discardableResult
    func recordFailure(
        _ turn: FailedTurn, error: any Error, agent: AgentDefinition.ID, agentName: String,
        stopping target: UsageSessionRef?
    ) -> Bool {
        let hit = UsageLimitHit(error: error, agentText: turn.agentText, now: now())
        let current = providers[agent].flatMap { limit in
            limit.status == .reached && now().timeIntervalSince(limit.updatedAt) < Self.statusFreshness ? limit : nil
        }
        guard hit != nil || current != nil else { return false }
        if let hit {
            // A structured status knows the reset to the second; the message rounds it.
            report(
                agent, agentName: agentName, status: .reached, window: hit.window ?? current?.window,
                resetsAt: current?.resetsAt ?? hit.resetsAt, utilization: current?.utilization, message: hit.message)
        }
        guard let target, target.isPromptable else { return true }
        var limited = sessions[target.id] ?? LimitedSession(target: target, work: turn.work)
        limited.target = target
        limited.work = turn.work
        if resumed.contains(target.id), let resumeAt = resumeTime(for: agent), let limit = providers[agent] {
            limited.resumeAt = resumeAt
            Task { await alerts.post(.rescheduled(limit, session: target, at: resumeAt)) }
        }
        sessions[target.id] = limited
        changed()
        return true
    }

    /// A turn that ended normally.
    func recordTurnEnded(_ reason: StopReason, in target: UsageSessionRef) {
        guard reason == .endTurn else { return }
        // The user carried on by hand, so a scheduled resume would only repeat the work.
        resumed.remove(target.id)
        var didChange = sessions.removeValue(forKey: target.id) != nil
        // With no reset time to wait for, a model answering is the only sign the limit lifted.
        if let limit = providers[target.agent], limit.status == .reached, limit.resetsAt == nil {
            clearLimit(of: target.agent, resumingScheduled: false)
            didChange = true
        }
        if didChange {
            changed()
        }
    }

    // MARK: - What the user chooses

    func resumeAtReset(_ id: UsageSessionRef.ID) {
        guard var limited = sessions[id], let resumeAt = resumeTime(for: id.agent) else { return }
        limited.resumeAt = resumeAt
        sessions[id] = limited
        changed()
    }

    /// Schedules every session the provider's limit stopped.
    func resumeAllAtReset(of agent: AgentDefinition.ID) {
        guard let resumeAt = resumeTime(for: agent) else { return }
        for (id, var limited) in sessions where id.agent == agent && limited.resumeAt == nil {
            limited.resumeAt = resumeAt
            sessions[id] = limited
        }
        changed()
    }

    func cancelResume(_ id: UsageSessionRef.ID) {
        guard var limited = sessions[id], limited.resumeAt != nil else { return }
        limited.resumeAt = nil
        sessions[id] = limited
        changed()
    }

    /// Quiet until the reset, then one notification that the provider is available again.
    func snoozeUntilReset(_ agent: AgentDefinition.ID) {
        guard var limit = providers[agent] else { return }
        limit.isSnoozed = true
        providers[agent] = limit
        pendingAlerts.removeValue(forKey: agent)?.cancel()
        changed()
    }

    func unsnooze(_ agent: AgentDefinition.ID) {
        guard var limit = providers[agent], limit.isSnoozed else { return }
        limit.isSnoozed = false
        providers[agent] = limit
        changed()
    }

    /// Hides the banner until the provider's status changes.
    func dismiss(_ agent: AgentDefinition.ID) {
        guard var limit = providers[agent] else { return }
        limit.isDismissed = true
        providers[agent] = limit
        changed()
    }

    func perform(_ action: LimitAlertAction) {
        switch action {
        case .resumeAtReset(let agent): resumeAllAtReset(of: agent)
        case .snoozeUntilReset(let agent): snoozeUntilReset(agent)
        case .show(let target): host?.show(target)
        }
    }

    // MARK: - What sessions show

    /// The provider's limit while it's in force, for places that show it whatever session is open:
    /// the status bar, the sidebar.
    func limitStatus(for agent: AgentDefinition.ID) -> LimitStatus? {
        guard let limit = providers[agent], isInForce(limit) else { return nil }
        return limit.limitStatus()
    }

    /// The limit as it applies to one of the provider's sessions, for that session's banner: with
    /// the resume it can offer, and nothing once the user dismissed or snoozed a warning.
    func limitStatus(agent: AgentDefinition.ID, session: SessionID) -> LimitStatus? {
        guard let limit = providers[agent], isInForce(limit) else { return nil }
        let limited = sessions[UsageSessionRef.ID(agent: agent, session: session)]
        switch limit.status {
        case .warning:
            guard !limit.isDismissed, !limit.isSnoozed else { return nil }
            return limit.limitStatus()
        case .reached:
            guard !limit.isDismissed || limited != nil else { return nil }
            guard let limited else { return limit.limitStatus() }
            if let resumeAt = limited.resumeAt {
                return limit.limitStatus(resume: .scheduled(resumeAt))
            }
            return limit.limitStatus(resume: limit.resetsAt == nil ? .unavailable : .offered)
        }
    }

    // MARK: - Due work

    /// Clears limits whose reset has passed and runs resumes that are due. Runs on its own timer,
    /// and should also run on wake and when the system clock changes.
    func processDue() {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        let now = now()
        for limit in providers.values {
            let isExpired =
                limit.resetsAt.map { $0 <= now } ?? (now.timeIntervalSince(limit.updatedAt) > Self.unknownResetExpiry)
            if isExpired {
                clearLimit(of: limit.agent, resumingScheduled: false)
            }
        }
        if host != nil {
            let due = sessions.values.filter { $0.resumeAt.map { $0 <= now } ?? false }
            for limited in due {
                sessions[limited.id] = nil
                Task { await resume(limited) }
            }
        }
        changed()
    }

    private func resume(_ limited: LimitedSession) async {
        let session = await host?.resumableSession(limited.target)
        switch session?.resumeReadiness {
        case .ready?:
            resumeAttempts[limited.id] = nil
            resumed.insert(limited.id)
            await session?.resume(with: limited.work.resumePrompt)
        case .busy?:
            resumeAttempts[limited.id] = nil
        case .unavailable?, nil:
            retry(limited)
        }
    }

    private func retry(_ limited: LimitedSession) {
        let attempts = resumeAttempts[limited.id, default: 0] + 1
        guard attempts <= Self.maxResumeAttempts else {
            resumeAttempts[limited.id] = nil
            Task { await alerts.post(.resumeFailed(limited.target)) }
            return
        }
        resumeAttempts[limited.id] = attempts
        // The session may have hit the limit again while this one was out looking for it.
        guard sessions[limited.id] == nil else { return }
        var later = limited
        later.resumeAt = now().addingTimeInterval(Self.retryInterval)
        sessions[limited.id] = later
        changed()
    }

    // MARK: - Bookkeeping

    private func report(
        _ agent: AgentDefinition.ID, agentName: String, status: ProviderLimit.Status, window: RateLimitInfo.Window?,
        resetsAt: Date?, utilization: Double?, message: String?
    ) {
        let previous = providers[agent]
        let isSameIncident = previous?.status == status && Self.isSameMinute(previous?.resetsAt, resetsAt)
        var limit = previous ?? ProviderLimit(agent: agent, agentName: agentName, status: status, updatedAt: now())
        limit.agentName = agentName
        limit.status = status
        limit.window = window ?? (isSameIncident ? previous?.window : nil)
        limit.resetsAt = resetsAt ?? (isSameIncident ? previous?.resetsAt : nil)
        limit.utilization = utilization ?? (isSameIncident ? previous?.utilization : nil)
        limit.message = message ?? (isSameIncident ? previous?.message : nil)
        limit.updatedAt = now()
        if !isSameIncident {
            limit.hasAlerted = false
            limit.isDismissed = false
        }
        providers[agent] = limit
        // Hitting the weekly limit right after the session one pushes every scheduled resume back.
        if let resetsAt = limit.resetsAt, status == .reached {
            let earliest = resetsAt.addingTimeInterval(Self.resetMargin)
            for (id, var limited) in sessions where id.agent == agent {
                if let resumeAt = limited.resumeAt, resumeAt < earliest {
                    limited.resumeAt = earliest
                    sessions[id] = limited
                }
            }
        }
        scheduleAlert(for: agent)
        changed()
    }

    private func clearLimit(of agent: AgentDefinition.ID, resumingScheduled: Bool) {
        guard let limit = providers.removeValue(forKey: agent) else { return }
        pendingAlerts.removeValue(forKey: agent)?.cancel()
        guard limit.status == .reached else { return }
        if limit.isSnoozed {
            Task { await alerts.post(.availableAgain(limit)) }
        }
        for (id, var limited) in sessions where id.agent == agent {
            if limited.resumeAt == nil {
                sessions[id] = nil
            } else if resumingScheduled {
                // The provider says it's available, so there's no reason to wait out the margin.
                limited.resumeAt = now()
                sessions[id] = limited
            }
        }
    }

    private func resumeTime(for agent: AgentDefinition.ID) -> Date? {
        providers[agent]?.resetsAt.map { $0.addingTimeInterval(Self.resetMargin) }
    }

    private func isInForce(_ limit: ProviderLimit) -> Bool {
        limit.resetsAt.map { $0 > now() } ?? true
    }

    private func scheduleAlert(for agent: AgentDefinition.ID) {
        pendingAlerts[agent]?.cancel()
        pendingAlerts[agent] = Task { [weak self] in
            try? await Task.sleep(for: Self.alertDelay)
            guard !Task.isCancelled else { return }
            await self?.postAlert(for: agent)
        }
    }

    private func postAlert(for agent: AgentDefinition.ID) async {
        pendingAlerts[agent] = nil
        guard var limit = providers[agent], !limit.hasAlerted, !limit.isSnoozed, !limit.isDismissed, isInForce(limit)
        else { return }
        limit.hasAlerted = true
        providers[agent] = limit
        changed()
        switch limit.status {
        case .reached:
            let stopped = sessions.values.filter { $0.id.agent == agent && $0.resumeAt == nil }.map(\.target)
            // Sessions that hit the limit again after resuming already said so, quietly.
            let rescheduled = sessions.values.contains { $0.id.agent == agent && resumed.contains($0.id) }
            if stopped.isEmpty, rescheduled { return }
            await alerts.post(.reached(limit, sessions: stopped.sorted { ($0.title ?? "") < ($1.title ?? "") }))
        case .warning:
            await alerts.post(.warning(limit))
        }
    }

    /// Saves and re-arms the timer for the next reset or resume.
    private func changed() {
        store.save(
            UsageLimitsSnapshot(
                providers: providers.values.sorted { $0.agent.rawValue < $1.agent.rawValue },
                sessions: sessions.values.sorted { $0.target.session.rawValue < $1.target.session.rawValue }
            ))
        updateSendGate()
        let next = (providers.values.compactMap(\.resetsAt) + sessions.values.compactMap(\.resumeAt)).min()
        timer.schedule(at: next, now: now()) { [weak self] in self?.processDue() }
    }

    /// Tells the host which agents refuse requests, in `LimitStatus`'s words without the countdown,
    /// which would go stale on a disabled button.
    private func updateSendGate() {
        guard let host else { return }
        var current: [AgentDefinition.ID: String] = [:]
        for limit in providers.values where limit.status == .reached && isInForce(limit) {
            let status = limit.limitStatus()
            current[limit.agent] = [status.headline, limit.resetsAt.map { "resets \(DSFormat.time($0, now: now()))" }]
                .compactMap(\.self).joined(separator: " · ")
        }
        for agent in Set(gated.keys).union(current.keys) where gated[agent] != current[agent] {
            host.setUsageLimit(current[agent], for: agent)
        }
        gated = current
    }

    private static func isSameMinute(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (let lhs?, let rhs?): abs(lhs.timeIntervalSince(rhs)) < 60
        // A message without a reset time doesn't make a new incident of a known one.
        case (_?, nil): true
        case (nil, _?): false
        }
    }
}
