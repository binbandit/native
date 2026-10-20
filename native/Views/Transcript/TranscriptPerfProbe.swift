#if DEBUG || NATIVE_PERF
import CodeThemes
import SwiftUI
import os

/// Temporary, for measuring (removed once measured): logs whether each code block that appears
/// after a transcript does had its colors when it appeared. `-nativeTranscriptCodeProbe YES`;
/// `-nativeTranscriptOpeningColors NO` turns the opening colors off for comparison.
enum TranscriptPerfProbe {
    static let isOn = UserDefaults.standard.bool(forKey: "nativeTranscriptCodeProbe")
    static let skipsOpeningColors =
        UserDefaults.standard.object(forKey: "nativeTranscriptOpeningColors") as? Bool == false
    private static let logger = Logger(subsystem: "Native", category: "TranscriptProbe")
    private static var appeared: ContinuousClock.Instant?

    static func transcriptAppeared() {
        guard isOn, appeared == nil else { return }
        appeared = .now
        logger.notice("transcript appeared")
    }

    /// `-nativeTranscriptPlainText YES`: reply sections without text selection.
    static let plainText = UserDefaults.standard.bool(forKey: "nativeTranscriptPlainText")
    private static var linesBodies = 0

    /// Counts `StandardTranscriptLines` bodies, which a streamed chunk shouldn't run.
    static func linesBodyRan(count: Int) {
        guard isOn else { return }
        linesBodies += 1
        logger.notice("earlier lines body \(linesBodies) (\(count) lines)")
    }

    private static var rendered: Set<Int> = []
    private static var lastScroll: CGPoint?

    /// The scroll view's content height and offset, when either moved by more than a screenful.
    static func scrolled(_ geometry: ScrollGeometry) {
        guard isOn else { return }
        let now = CGPoint(x: geometry.contentSize.height, y: geometry.contentOffset.y)
        if let last = lastScroll, abs(last.x - now.x) < 1000, abs(last.y - now.y) < 1000 { return }
        lastScroll = now
        logger.notice(
            "scroll content \(Int(now.x)) offset \(Int(now.y)) visible \(Int(geometry.visibleRect.height))")
    }

    static func revealed(_ lineID: String?, index: Int) {
        guard isOn else { return }
        logger.notice("reveal item \(index) line \(lineID ?? "none", privacy: .public)")
    }

    /// Called from a code block's body: whether its colors were there the first time it rendered.
    static func codeRendered(_ code: String, language: String?) {
        guard isOn, let appeared, let language = language.flatMap(CodeLanguage.named),
            rendered.insert(code.hashValue).inserted
        else { return }
        let elapsed = Int((ContinuousClock.now - appeared) / .milliseconds(1))
        let colored = CodeHighlightCache.shared.cached(code, language: language) != nil
        logger.notice("code \(colored ? "colored" : "plain", privacy: .public) at \(elapsed) ms")
    }
}

extension View {
    @ViewBuilder func transcriptPerfTextSelection() -> some View {
        if TranscriptPerfProbe.plainText {
            self
        } else {
            textSelection(.enabled)
        }
    }
}
#endif
