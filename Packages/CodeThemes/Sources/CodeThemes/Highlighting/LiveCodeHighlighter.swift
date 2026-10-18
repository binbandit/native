import Observation

/// Highlighting for code that changes while it's shown, like a code block in a reply that's still
/// streaming in. A view asks it for the segments on every render; it answers at once with the best
/// colors it has, and sees to it that the code as it is now gets highlighted off the main thread.
///
/// - Code that grew keeps the colors of the part it had; only the new text draws plain, briefly.
/// - While the code keeps changing it highlights at most once per `interval`, always the newest
///   text, and the last version always gets its colors.
/// - Code that stops changing goes into the cache once: each version replaces the one before it.
///
/// Driven by rendering rather than `.task(id:)` or `onChange(of:)`: a view updated many times a
/// second, as a streaming code block is, can miss those altogether, the last change included, which
/// left a finished block plain for good. A render of the text it shows can't be missed.
@MainActor @Observable
public final class LiveCodeHighlighter {
    private struct Highlight {
        let code: String
        let language: String
        let segments: [CodeSegment]
    }

    /// The newest colors and the code they're for. Renders observe `revision` instead, so taking
    /// colors from the cache while rendering doesn't invalidate the render.
    @ObservationIgnored private var latest: Highlight?
    /// Bumped whenever new colors arrive, to redraw.
    private var revision = 0
    /// The code to highlight next, and the pass working through it.
    @ObservationIgnored private var wanted: (code: String, language: CodeLanguage)?
    @ObservationIgnored private var pass: Task<Void, Never>?
    @ObservationIgnored private var lastPass: ContinuousClock.Instant?
    /// What this highlighter last put in the cache.
    @ObservationIgnored private var stored: String?

    @ObservationIgnored private let cache: CodeHighlightCache
    @ObservationIgnored private let interval: Duration

    public init(cache: CodeHighlightCache = .shared, interval: Duration = .milliseconds(100)) {
        self.cache = cache
        self.interval = interval
    }

    /// What to draw for `code` now; nil to draw it plain (an unknown language, or nothing to go on
    /// yet).
    public func segments(for code: String, language: CodeLanguage?) -> [CodeSegment]? {
        _ = revision
        guard let language else { return nil }
        if let latest, latest.code == code, latest.language == language.id {
            return latest.segments
        }
        if let cached = cache.cached(code, language: language) {
            latest = Highlight(code: code, language: language.id, segments: cached)
            return cached
        }
        request(code, language)
        guard let latest, latest.language == language.id else { return nil }
        return CodeHighlighter.segments(latest.segments, of: latest.code, reusedFor: code)
    }

    private func request(_ code: String, _ language: CodeLanguage) {
        guard wanted?.code != code || wanted?.language.id != language.id else { return }
        wanted = (code, language)
        if pass == nil {
            pass = Task { await self.work() }
        }
    }

    private func work() async {
        while wanted != nil {
            if let lastPass {
                try? await Task.sleep(until: lastPass + interval, clock: .continuous)
            }
            // The newest text, which may have changed during the wait.
            guard let target = wanted else { break }
            wanted = nil
            // Asked for again while it was being highlighted.
            if let latest, latest.code == target.code, latest.language == target.language.id { continue }
            lastPass = .now
            let segments = await CodeHighlightCache.segments(target.code, language: target.language)
            latest = Highlight(code: target.code, language: target.language.id, segments: segments)
            revision += 1
            // Nothing newer asked for: this is the code as it stands, worth keeping.
            if wanted == nil {
                cache.store(segments, for: target.code, language: target.language, replacing: stored)
                stored = target.code
            }
        }
        pass = nil
    }

    /// Waits for the highlighting asked for so far to land.
    func settled() async {
        while let pass {
            await pass.value
        }
    }
}
