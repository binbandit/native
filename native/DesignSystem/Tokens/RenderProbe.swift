// TEMPORARY (streaming investigation): counts view body evaluations in the log. In DesignSystem so the
// companion, which compiles DesignSystem and MarkdownView, sees it too. Remove before landing.
#if DEBUG
import os

nonisolated enum RenderProbe {
    static let logger = Logger(subsystem: "Native", category: "Probe")

    static func hit(_ name: String) {
        logger.info("render \(name, privacy: .public)")
    }

    static func note(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
#endif
