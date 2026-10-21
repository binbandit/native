import Foundation

// How turns end, and what the transcript says once they have. Whatever a turn leaves open is settled
// when it ends, with only what Native knows: a stop cut its calls short, a crash interrupted them, and
// otherwise the agent never said how they went. A retry follows its message through, and output that
// arrives after a stop is never shown as part of the turn the user saw end.
extension SessionState {
    /// Wraps up a prompt turn. ACP v1 has no status for a call that didn't run to its end, so every
    /// call still open is settled here, its clock stopped; any stop other than a normal one is noted in
    /// the transcript.
    public mutating func endTurn(_ stopReason: StopReason, at date: Date = .now) {
        let start = openTurn ?? suspendedTurn ?? turnStarts.last
        if stopReason == .cancelled {
            settleOpenCalls(as: .cancelled, at: date)
            if let start {
                // Claude Code reports a command the stop killed as refused by the user; codex-acp, as
                // failed without an exit code.
                settleTrailingCalls(of: start, as: .cancelled) {
                    $0.status == .failed && ($0.nonExecutionKind == "user-rejected" || $0.wasKilled)
                }
            }
        } else {
            settleOpenCalls(as: .unreported, at: date)
        }
        settleRetry(as: stopReason == .error ? .gaveUp : .wentThrough)
        if let start {
            stopClock(of: start, as: stopReason, at: date)
        }
        openTurn = nil
        suspendedTurn = nil
        isAwaitingRetry = false
        isAfterStop = stopReason == .cancelled
        switch stopReason {
        case .endTurn: break
        case .cancelled: appendNotice(Self.stoppedNotice, isError: false)
        case .maxTokens: appendNotice("Stopped: the response hit the token limit.", isError: true)
        case .maxTurnRequests: appendNotice("Stopped: the turn hit its request limit.", isError: true)
        case .refusal: appendNotice("The agent declined to continue.", isError: true)
        // `.error` is Native's own, set when the prompt threw: `failTurn` explains it.
        case .error: break
        case .other(let reason): appendNotice("Stopped: \(reason).", isError: true)
        }
    }

    /// The prompt failed instead of ending with a stop reason, for the reason `message` gives. With
    /// `retry`, the failure is passing and Native sends the message again by itself: the turn waits for
    /// that rather than ending, under a notice that follows the retry through (`TranscriptNotice.Retry`).
    public mutating func failTurn(_ message: String, retry: DeliveryRetry? = nil, at date: Date = .now) {
        // A retry that failed again before the agent did anything stays one notice; one that got
        // somewhere went through, and what failed after it is news of its own.
        let undelivered = retryNoticeIndex.flatMap { $0 == items.count - 1 ? $0 : nil }
        guard let retry else {
            if let undelivered, case .notice(var notice) = items[undelivered] {
                retryNoticeIndex = nil
                notice.show(failure: message)
                replaceItem(at: undelivered, with: .notice(notice))
            } else {
                settleRetry(as: .wentThrough)
                appendNotice(message, isError: true)
            }
            endTurn(.error, at: date)
            return
        }
        settleOpenCalls(as: .unreported, at: date)
        let waiting = TranscriptNotice.Retry(delivery: retry, progress: .waiting)
        if let undelivered, case .notice(var notice) = items[undelivered] {
            notice.show(waiting)
            replaceItem(at: undelivered, with: .notice(notice))
        } else {
            settleRetry(as: .wentThrough)
            retryNoticeIndex = items.count
            appendItem(.notice(TranscriptNotice(waiting)))
        }
        // A message the transcript doesn't show has no turn of its own to wait.
        if let start = openTurn ?? suspendedTurn {
            turnClocks[start]?.suspendedAt = date
            suspendedTurn = start
        }
        isAwaitingRetry = true
        openTurn = nil
    }

    /// The message Native kept after a passing failure went out again: its turn carries on. False
    /// when no turn was waiting for one.
    @discardableResult
    public mutating func retryTurn() -> Bool {
        guard isAwaitingRetry else { return false }
        isAwaitingRetry = false
        if let start = suspendedTurn {
            suspendedTurn = nil
            turnClocks[start]?.suspendedAt = nil
            openTurn = start
        }
        updateRetry(to: .retrying)
        return true
    }

    /// The wait for a retry ended without one (the user stopped it, or another message went first):
    /// the turn ends as failed when it did, and its notice no longer promises another try.
    public mutating func stopRetrying(at date: Date = .now) {
        guard isAwaitingRetry else { return }
        isAwaitingRetry = false
        settleRetry(as: .gaveUp)
        if let start = suspendedTurn {
            suspendedTurn = nil
            stopClock(of: start, as: .error, at: date)
        }
    }

    /// Native sent the agent a message the transcript doesn't show (a task's message, a recovery
    /// prompt). It's a request of its own, though it has no turn here: a retry still waiting won't
    /// come first, and what the agent answers comes after it, not after an earlier stop.
    public mutating func noteUnshownPrompt(at date: Date = .now) {
        stopRetrying(at: date)
        isAfterStop = false
    }

    /// The latest turn was cut off: the agent or Native's host stopped unexpectedly, at `date` as
    /// closely as anyone knows. What it left running, or the cut killed, was interrupted. The turn
    /// itself goes on if Native resumes it.
    public mutating func interruptTurn(at date: Date) {
        guard let start = openTurn ?? turnStarts.last else { return }
        settleInterruption(of: start, at: date)
    }

    /// The agent's history has Native's message telling it its turn was cut off (`RecoveryPrompt`).
    /// The turn it interrupted ends there the way a live recovery ends it, and the message shows as
    /// what Native told the agent, not as the user's; the agent's answer carries the turn on, as it
    /// did live.
    mutating func recordReplayedRecovery(_ prompt: RecoveryPrompt, text: String) {
        if let start = turnStarts.last {
            settleInterruption(of: start, at: nil)
        }
        // Recovery resumes the same turn, but a later stop belongs to the resumed work rather than
        // the earlier interruption. Only repeated markers within one segment are duplicates.
        replayedStops[promptIndices.last ?? 0] = nil
        var notice = TranscriptNotice(text: prompt.notice, isError: false)
        notice.sentToAgent = text
        appendItem(.notice(notice))
    }

    /// What the cut-off turn starting at `start` left running, or the cut killed, was interrupted.
    private mutating func settleInterruption(of start: Int, at date: Date?) {
        let turn = turnRange(containing: start)
        for index in openCallIndices.filter(turn.contains) {
            settleCall(at: index, as: .interrupted, at: date)
        }
        // Unreported ones were open in the replay a reload brought back.
        for index in turn {
            guard case .toolCall(let call) = items[index], call.status == .unreported else { continue }
            settleCall(at: index, as: .interrupted, at: date)
        }
        settleTrailingCalls(of: start, as: .interrupted) { $0.wasKilled }
    }

    /// The agent finished replaying its history (`session/load`). Nothing in history runs any more:
    /// a call it left open ended without the agent saying how, and a command that failed without an
    /// exit code at the end of its turn was cut off there, by a stop or a crash.
    public mutating func endReplay() {
        for index in openCallIndices {
            guard case .toolCall(let call) = items[index], call.startedAt == nil else { continue }
            settleCall(at: index, as: .unreported, at: nil)
        }
        for start in [0] + turnStarts where turnClocks[start] == nil {
            settleTrailingCalls(of: start, as: .interrupted) { $0.wasKilled }
        }
    }

    static let stoppedNotice = "Stopped."
    static let lateOutputNotice = "The agent kept going after the stop."

    /// The agent's history says the user stopped the turn being replayed (`InterruptionMarker`): it
    /// ends the way a live stop does. A live turn reports its own ending, so a marker that arrives
    /// during one, or after its end, adds nothing.
    mutating func recordReplayedStop(_ marker: InterruptionMarker) {
        let start = promptIndices.last ?? 0
        guard openTurn == nil, turnClocks[start]?.stopReason == nil, replayedStops[start] == nil else { return }
        replayedStops[start] = .cancelled
        if marker == .whileUsingTools {
            // History doesn't say why those calls failed, or that they ended; the marker says the stop
            // cut them off.
            settleTrailingCalls(of: start, as: .cancelled) { $0.status == .failed || !$0.status.isFinished }
        }
        appendNotice(Self.stoppedNotice, isError: false)
    }

    /// After a stop, a new item from the agent didn't come from the turn the user saw end: it starts a
    /// turn of its own, opened by a notice that says so. Updates to the stopped turn's own items stay
    /// where they are.
    mutating func beginLateOutputIfStopped() {
        guard isAfterStop, openTurn == nil else { return }
        isAfterStop = false
        lateOutputStarts.insert(items.count)
        turnStarts.append(items.count)
        appendNotice(Self.lateOutputNotice, isError: false)
    }

    // MARK: - Settling

    /// Ends the clock of the live turn starting at `start`, unless it already ended: a request the
    /// transcript doesn't show ends in the turn before it, which it mustn't rewrite. One waiting for a
    /// retry ended when its message failed: the wait wasn't work.
    private mutating func stopClock(of start: Int, as stopReason: StopReason, at date: Date) {
        guard var clock = turnClocks[start], clock.endedAt == nil else { return }
        clock.endedAt = clock.suspendedAt ?? date
        clock.suspendedAt = nil
        clock.stopReason = stopReason
        turnClocks[start] = clock
    }

    /// Closes every call still open as `status`: once a turn is over, nothing in it runs.
    private mutating func settleOpenCalls(as status: ToolCallStatus, at date: Date?) {
        for index in openCallIndices.sorted() {
            settleCall(at: index, as: status, at: date)
        }
    }

    /// Gives `status` to the calls that end the turn starting at `start`, the ones still running when
    /// it was cut off, where `wasCutOff` agrees. Earlier calls ended before the cut; notices Native
    /// added after them don't count.
    private mutating func settleTrailingCalls(
        of start: Int, as status: ToolCallStatus, where wasCutOff: (ToolCallState) -> Bool
    ) {
        for index in turnRange(containing: start).reversed() {
            switch items[index] {
            // A recovery's notice replaces a prompt boundary: calls before it belong to an earlier
            // attempt, even though the recovered work stays in the same visible turn.
            case .notice(let notice) where notice.sentToAgent != nil: return
            case .notice: continue
            case .toolCall(let call) where wasCutOff(call): settleCall(at: index, as: status, at: nil)
            case .toolCall: continue
            default: return
            }
        }
    }

    /// Gives the call at `index` a status of Native's. A live call's clock stops at `date`, never
    /// before it started; one that already stopped keeps its time.
    private mutating func settleCall(at index: Int, as status: ToolCallStatus, at date: Date?) {
        guard case .toolCall(var call) = items[index] else { return }
        call.status = status
        call.permission = nil
        if let startedAt = call.startedAt, call.finishedAt == nil {
            call.finishedAt = date.map { max($0, startedAt) }
        }
        replaceItem(at: index, with: .toolCall(call))
    }

    /// Moves the retry notice on, keeping it for later steps unless the retry is over.
    private mutating func updateRetry(to progress: TranscriptNotice.Retry.Progress) {
        guard let index = retryNoticeIndex, case .notice(var notice) = items[index], var retry = notice.retry else {
            return
        }
        retry.progress = progress
        notice.show(retry)
        replaceItem(at: index, with: .notice(notice))
    }

    /// The retry is over, as `progress` says, unless it never went out: a notice still waiting only
    /// ever gives up.
    private mutating func settleRetry(as progress: TranscriptNotice.Retry.Progress) {
        guard let index = retryNoticeIndex, case .notice(let notice) = items[index], let retry = notice.retry else {
            return
        }
        updateRetry(to: retry.progress == .waiting ? .gaveUp : progress)
        retryNoticeIndex = nil
    }
}
