import ACP
import Foundation

@testable import Native

/// Exercises the actual app store without a window, host, agent or on-device model. The wrapper's
/// executable name includes the isolated instance, so its standard defaults belong only to this check.
@main
@MainActor
private struct SessionTitlesRegression {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    private final class HeldTitler: SessionTitler {
        var isHeld = true
        var answer: String? = "Fix login callback"
        private(set) var calls = 0

        func title(for request: TitleRequest) async throws -> String? {
            calls += 1
            while isHeld { try await Task.sleep(for: .milliseconds(10)) }
            return answer
        }
    }

    static func main() async {
        guard Bundle.main.bundleIdentifier == nil,
            ProcessInfo.processInfo.processName.hasPrefix("session-titles-")
        else {
            print("FAIL: run through the isolated command-line wrapper")
            exit(1)
        }
        let keys = ["sessionTitles.user", "sessionTitles.generated", "sessionTitles.fallback"]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        defer { for key in keys { UserDefaults.standard.removeObject(forKey: key) } }
        do {
            try await check(retrySucceeds: true)
            try await check(retrySucceeds: false)
            print("PASS: discarded title requests retry after re-enable without replenishing the retry budget")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    static func check(retrySucceeds: Bool) async throws {
        let titles = SessionTitles()
        let titler = HeldTitler()
        let key = SessionTitles.Key(agent: .init(rawValue: "fixture"), session: SessionID(UUID().uuidString))
        let request = TitleRequest(projectName: "fixture", prompt: "Fix login", instructions: nil)
        var enabled = true
        let initial = Task {
            await titles.generateIfNeeded(for: key, request: request, using: titler, isAllowed: { enabled })
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while titler.calls == 0 {
            guard ContinuousClock.now < deadline else { throw Failure(description: "The provider did not start") }
            try await Task.sleep(for: .milliseconds(10))
        }
        enabled = false
        titler.isHeld = false
        await initial.value
        try require(titles.generatedTitle(for: key) == nil, "A disabled provider's result was applied")
        enabled = true
        titler.answer = retrySucceeds ? "Fix login callback" : nil
        await titles.generateIfNeeded(
            for: key, request: request, using: titler, isFirstPrompt: false, isAllowed: { enabled })
        try require(titler.calls == 2, "The re-enabled provider was not retried")
        try require(
            titles.generatedTitle(for: key) == (retrySucceeds ? "Fix login callback" : nil),
            "The retry did not keep the expected title")
        titler.answer = "Another title"
        await titles.generateIfNeeded(
            for: key, request: request, using: titler, isFirstPrompt: false, isAllowed: { enabled })
        try require(titler.calls == 2, "A discarded result replenished the retry budget")
    }
}
