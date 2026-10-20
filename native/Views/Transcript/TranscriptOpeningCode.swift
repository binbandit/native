import ACP
import CodeThemes
import SwiftUI

/// The code a transcript shows when it appears, at its end, colored before it appears: drawn first
/// and highlighted after, the code on screen stayed plain for 100–200 ms after a session reopened,
/// while the main thread laid out the transcript's first frame.
enum TranscriptOpeningCode {
    struct Block: Hashable, Sendable {
        let code: String
        let language: CodeLanguage
    }

    /// Off until it's been seen working in the running app: `-transcriptOpeningColors YES`.
    static let isEnabled = UserDefaults.standard.bool(forKey: "transcriptOpeningColors")

    /// How long a transcript waits for colors before showing anyway: highlighting a screenful of
    /// code takes a few milliseconds, so only something pathological (a huge block) gets here.
    static let patience = Duration.milliseconds(300)

    /// The code blocks in the last `height` points or so of `items` that have no colors yet, as the
    /// transcript's code blocks will ask for them (`TranscriptCodeBlock`, `HighlightedCode`).
    static func uncolored(in items: [TranscriptItem], height: CGFloat) -> [Block] {
        var blocks: [Block] = []
        var covered: CGFloat = 0
        // Rows a little past the top of the screen as well: the lazy stack builds a few ahead.
        let reach = height * 1.5
        for item in items.reversed() {
            guard covered < reach else { break }
            covered += estimatedHeight(of: item)
            blocks += codeBlocks(in: item).filter {
                CodeHighlightCache.shared.cached($0.code, language: $0.language) == nil
            }
        }
        return blocks
    }

    /// Highlights `blocks` into the shared cache, all at once off the main thread, for at most
    /// `patience`. Past that the highlighting goes on, and the blocks color as it lands.
    static func color(_ blocks: [Block]) async {
        guard !blocks.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finish = TranscriptOpeningCodeWait(continuation)
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for block in blocks {
                        group.addTask {
                            _ = await CodeHighlightCache.shared.highlight(block.code, language: block.language)
                        }
                    }
                }
                finish()
            }
            Task {
                try? await Task.sleep(for: patience)
                finish()
            }
        }
    }

    /// The code blocks `item` shows while closed: in replies and session messages (Markdown) and in
    /// prompts (fences). Reasoning and tool output start closed.
    private static func codeBlocks(in item: TranscriptItem) -> [Block] {
        let fenced: [(code: String, language: String?)]
        switch item {
        case .message(let message) where message.role == .agent:
            fenced = markdownCode(in: message.text)
        case .message(let message) where message.role == .user && FencedText.containsFence(message.text):
            fenced = FencedText.segments(of: message.text).compactMap { segment in
                if case .code(let code, let language, _) = segment { (code, language) } else { nil }
            }
        case .sessionMessage(let message):
            fenced = markdownCode(in: message.text)
        case .message, .toolCall, .notice, .subagent:
            fenced = []
        }
        return fenced.compactMap { block in
            guard let language = block.language.flatMap(CodeLanguage.named) else { return nil }
            return Block(code: TranscriptCodeBlock.shownCode(block.code), language: language)
        }
    }

    /// Section by section, as replies are shown (`String.markdownSections`), so the parses are the
    /// ones the rows look up.
    private static func markdownCode(in text: String) -> [(code: String, language: String?)] {
        text.markdownSections.flatMap { MarkdownSectionView.codeBlocks(in: String($0)) }
    }

    /// Roughly how tall a row is, closed: enough to tell which rows the first screen shows.
    private static func estimatedHeight(of item: TranscriptItem) -> CGFloat {
        let rowHeight: CGFloat = 24
        switch item {
        case .message(let message) where message.role != .thought:
            // About 90 characters to a line of body text, each line 18 points.
            let lines = message.text.split(separator: "\n", omittingEmptySubsequences: false)
                .reduce(0) { $0 + 1 + $1.count / 90 }
            return CGFloat(lines) * 18
        case .sessionMessage(let message):
            return CGFloat(message.text.count / 90 + 2) * 18
        case .subagent:
            return rowHeight * 3
        case .message, .toolCall, .notice:
            return rowHeight
        }
    }
}

/// Resumes a wait once, whichever of its ends gets there first.
private final class TranscriptOpeningCodeWait {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func callAsFunction() {
        continuation?.resume()
        continuation = nil
    }
}
