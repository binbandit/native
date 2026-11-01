import Foundation
import Testing

@testable import ACP

struct RateLimitTests {
    // MARK: - Claude Code's structured status

    /// Shaped like the Agent SDK's `SDKRateLimitInfo`, as the adapter forwards it in `_meta`.
    @Test func decodesARejectedStatus() throws {
        let json = #"""
            {"status":"rejected","resetsAt":1792360800,"rateLimitType":"five_hour","utilization":1,"overageStatus":"rejected","overageResetsAt":1793000000,"overageDisabledReason":"out_of_credits","isUsingOverage":false,"surpassedThreshold":0.9}
            """#
        let info = try JSONDecoder().decode(RateLimitInfo.self, from: Data(json.utf8))
        #expect(info.status == .rejected)
        #expect(info.resetsAt == Date(timeIntervalSince1970: 1_792_360_800))
        #expect(info.window == .fiveHour)
        #expect(info.utilization == 1)
        #expect(info.overageDisabledReason == "out_of_credits")
        #expect(info.isBlocking)
        // Both the plan and the credits are exhausted; the earlier reset frees the user.
        #expect(info.blockedUntil == Date(timeIntervalSince1970: 1_792_360_800))
    }

    /// The adapter's own test sends this one: a warning with only the essentials.
    @Test func decodesAWarningInAUsageUpdate() throws {
        let line =
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"_meta":{"_claude/model":"claude-sonnet-4-6","_claude/rateLimit":{"resetsAt":1700000000,"status":"allowed_warning","utilization":0.9}},"sessionUpdate":"usage_update","size":200000,"used":2}}}"#
        guard case .sessionUpdate(let notification) = try Wire.event(line), case .usage(let usage) = notification.update
        else {
            Issue.record("Expected a usage update")
            return
        }
        #expect(usage.used == 2)
        let meta = try JSONDecoder().decode(UpdateWithMeta.self, from: Data(line.utf8)).params.update._meta
        let info = try #require(meta.rateLimit)
        #expect(info.status == .allowedWarning)
        #expect(info.isWarning && !info.isBlocking)
        #expect(info.window == nil)
        #expect(info.utilization == 0.9)
        #expect(info.resetsAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func oddMetaNeverFailsTheUsage() throws {
        let missing = try JSONDecoder().decode(MetaHolder.self, from: Data(#"{}"#.utf8))
        let modelOnly = try JSONDecoder().decode(MetaHolder.self, from: Data(#"{"_meta":{"_claude/model":"x"}}"#.utf8))
        let malformed = try JSONDecoder().decode(
            MetaHolder.self, from: Data(#"{"_meta":{"_claude/rateLimit":{"utilization":"high"}}}"#.utf8))
        let notAnObject = try JSONDecoder().decode(MetaHolder.self, from: Data(#"{"_meta":3}"#.utf8))
        #expect([missing, malformed, notAnObject].allSatisfy { $0._meta == UsageMeta() })
        #expect(modelOnly._meta == UsageMeta(model: "x"))

        let unknown = try JSONDecoder().decode(
            MetaHolder.self,
            from: Data(#"{"_meta":{"_claude/rateLimit":{"status":"throttled","rateLimitType":"daily"}}}"#.utf8))
        #expect(unknown._meta.rateLimit?.status == .other("throttled"))
        #expect(unknown._meta.rateLimit?.window == .other("daily"))
        #expect(unknown._meta.rateLimit?.isBlocking == false)
    }

    @Test func creditsDecideWhileInUse() {
        let covered = RateLimitInfo(
            status: .rejected, resetsAt: .distantFuture, overageStatus: .allowed, isUsingOverage: true)
        #expect(!covered.isBlocking)
        let closeToCap = RateLimitInfo(status: .rejected, overageStatus: .allowedWarning, isUsingOverage: true)
        #expect(closeToCap.isWarning)
        let notProvisioned = RateLimitInfo(
            status: .rejected, resetsAt: Date(timeIntervalSince1970: 10),
            overageResetsAt: Date(timeIntervalSince1970: 5))
        #expect(notProvisioned.blockedUntil == Date(timeIntervalSince1970: 10))
    }

    // MARK: - Limits reported as text

    private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    /// 2026-10-17 10:00 in Los Angeles.
    private var morning: Date { date(2026, 10, 17, 10, 0, in: losAngeles) }

    @Test func recognizesClaudeCodesFailedTurn() throws {
        let error = RPCError(
            code: -32603, message: "Internal error: You've hit your session limit · resets 3pm (America/Los_Angeles)",
            data: .object(["errorKind": .string("rate_limit")]))
        let hit = try #require(UsageLimitHit(error: error, now: morning, timeZone: .gmt))
        #expect(hit.message == "You've hit your session limit · resets 3pm (America/Los_Angeles)")
        #expect(hit.window == .fiveHour)
        // The zone in the message wins over the one passed in.
        #expect(hit.resetsAt == date(2026, 10, 17, 15, 0, in: losAngeles))
    }

    @Test func recognizesCodexsFailedTurn() throws {
        let message =
            "You’ve hit your usage limit. Visit https://chatgpt.com/settings/usage to purchase more credits or try again at 3:05 PM."
        let error = RPCError(
            code: -32603, message: "Internal error",
            data: .object(["message": .string(message), "codexErrorInfo": .string("usageLimitExceeded")]))
        let hit = try #require(UsageLimitHit(error: error, now: morning, timeZone: losAngeles))
        #expect(hit.message == message)
        #expect(hit.window == nil)
        #expect(hit.resetsAt == date(2026, 10, 17, 15, 5, in: losAngeles))
    }

    @Test func codexsErrorCodeIsEnoughWithoutKnownText() throws {
        let error = RPCError(
            code: -32603, message: "Internal error",
            data: .object(["message": .string("Usage cap reached."), "codexErrorInfo": .string("usageLimitExceeded")]))
        let hit = try #require(UsageLimitHit(error: error, now: morning))
        #expect(hit.message == "Usage cap reached.")
        #expect(hit.resetsAt == nil)
    }

    @Test func fallsBackToTheAgentsMessage() throws {
        let error = RPCError(code: -32603, message: "Internal error")
        let hit = try #require(
            UsageLimitHit(
                error: error, agentText: "You've reached your weekly limit · resets Oct 20, 9am", now: morning,
                timeZone: losAngeles))
        #expect(hit.window == .sevenDay)
        #expect(hit.resetsAt == date(2026, 10, 20, 9, 0, in: losAngeles))
    }

    @Test func otherFailuresAreNotLimits() {
        #expect(
            UsageLimitHit(
                error: RPCError(
                    code: -32603, message: "Internal error", data: .object(["errorKind": .string("overloaded")])))
                == nil)
        #expect(
            UsageLimitHit(
                error: RPCError(code: -32603, message: "Internal error: Claude is temporarily rate limited."),
                agentText: "Sorry, something went wrong.") == nil)
        #expect(UsageLimitHit(error: ACPConnectionError.disconnected) == nil)
        #expect(UsageLimitHit(text: "I've hit your limit of patience") == nil)
        #expect(UsageLimitHit.isLimitMessage("  You've hit your Opus limit · resets 5pm"))
        #expect(UsageLimitHit.isLimitMessage("Your org is out of usage · add funds to continue"))
        #expect(
            UsageLimitHit.isLimitMessage(
                "\u{00A0}\nYou\u{2019}ve hit your limit" + String(repeating: " and on", count: 5_000)))
        #expect(!UsageLimitHit.isLimitMessage(String(repeating: " ", count: 100) + "Done. You've hit your"))
    }

    @Test func readsResetTimes() {
        let cases: [(String, Date?)] = [
            ("You've hit your session limit · resets 3pm", date(2026, 10, 17, 15, 0, in: losAngeles)),
            (
                "You've hit your session limit · resets 3:30pm · progress saved",
                date(2026, 10, 17, 15, 30, in: losAngeles)
            ),
            // Already past today, so tomorrow.
            ("You've hit your session limit · resets 9am", date(2026, 10, 18, 9, 0, in: losAngeles)),
            (
                "You've hit your weekly limit · resets Oct 20, 3:30pm (Europe/London)",
                date(2026, 10, 20, 15, 30, in: TimeZone(identifier: "Europe/London") ?? .gmt)
            ),
            ("You've hit your weekly limit · resets Jan 2, 2027, 3pm", date(2027, 1, 2, 15, 0, in: losAngeles)),
            // A date without a year that's long past means next year.
            ("You've hit your weekly limit · resets Jan 2, 3pm", date(2027, 1, 2, 15, 0, in: losAngeles)),
            (
                "You’ve hit your usage limit. Try again at Oct 18th, 2026 3:05 PM.",
                date(2026, 10, 18, 15, 5, in: losAngeles)
            ),
            ("You've hit your fast limit · resets in 2h 30m", morning.addingTimeInterval(9_000)),
            ("You've hit your monthly spend limit · contact your admin to increase it", nil),
            ("You've hit your session limit · resets soon", nil),
        ]
        for (text, expected) in cases {
            #expect(UsageLimitHit.resetDate(in: text, now: morning, timeZone: losAngeles) == expected, "\(text)")
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .distantPast
    }
}

/// How `Usage` holds its extras: a non-optional `UsageMeta` that tolerates any `_meta`.
private struct MetaHolder: Decodable {
    var _meta = UsageMeta()
}

private struct UpdateWithMeta: Decodable {
    struct Params: Decodable {
        let update: MetaHolder
    }

    let params: Params
}

struct ProviderUsageReportTests {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .distantPast
    }

    /// As `claude-agent-acp`'s `formatUsageResponse` renders the SDK's `/usage` answer.
    @Test func readsClaudeCodesUsage() throws {
        let markdown = """
            ## Usage

            > Claude max subscription usage

            ### Limits

            **5-hour limit** — **42%** · Resets Oct 17, 3:00 PM PDT

            `████████░░░░░░░░░░░░`

            **Weekly · all models** — **18%** · Resets Oct 21, 9:00 AM PDT

            `████░░░░░░░░░░░░░░░░`

            **Weekly · Opus** — **0%**

            ---

            ### This session

            | Cost | API time | Active |
            """
        let report = try #require(ProviderUsageReport.parse(markdown, now: date(10, 17, 10, 0), timeZone: losAngeles))
        #expect(report.windows.map(\.name) == ["5-hour limit", "Weekly · all models", "Weekly · Opus"])
        #expect(report.windows.map(\.utilization) == [0.42, 0.18, 0])
        #expect(report.windows[0].resetsAt == date(10, 17, 15, 0))
        #expect(report.windows[1].resetsAt == date(10, 21, 9, 0))
        #expect(report.windows[2].resetsAt == nil)
    }

    /// As `codex-acp`'s `/status` renders its rate-limit snapshots.
    @Test func readsCodexsStatus() throws {
        let markdown = """
            **Model:** gpt-6.1-sol  \n**Context window:** 24% used (61.2k used / 258.4k)  \n**codex 5h limit:** 88% left (resets 15:00)  \n**codex Weekly limit:** 61% left (resets 09:30 on Oct 21)
            """
        let report = try #require(ProviderUsageReport.parse(markdown, now: date(10, 17, 10, 0), timeZone: losAngeles))
        #expect(report.windows.map(\.name) == ["5h limit", "Weekly limit"])
        #expect(report.windows.map(\.utilization) == [0.12, 0.39])
        #expect(report.windows.map(\.resetsAt) == [date(10, 17, 15, 0), date(10, 21, 9, 30)])
    }

    @Test func otherTextHasNoWindows() {
        #expect(ProviderUsageReport.parse("**Limits:** data not available yet") == nil)
        #expect(ProviderUsageReport.parse("## Context Usage") == nil)
    }
}
