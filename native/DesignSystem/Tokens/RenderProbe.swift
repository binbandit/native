// TEMPORARY (streaming investigation): counts view body evaluations in the log. In DesignSystem so the
// companion, which compiles DesignSystem and MarkdownView, sees it too. Remove before landing.
#if DEBUG
import Foundation
import os

nonisolated enum RenderProbe {
    static let logger = Logger(subsystem: "Native", category: "Probe")
    /// Off unless launched with `-renderProbe YES`, so CPU measurements don't pay for the logging.
    static let isEnabled = UserDefaults.standard.bool(forKey: "renderProbe")

    static func hit(_ name: String) {
        guard isEnabled else { return }
        logger.info("render \(name, privacy: .public)")
    }

    static func note(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        logger.info("\(text, privacy: .public)")
    }
}
#endif
