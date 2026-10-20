import ACP
import Foundation

/// A tool call in one line for the phone, in the Mac's own words: `ToolPresentation` (shared from
/// the Mac's transcript) decides the glyph, verb and subject, so a task reads the same on both.
struct CompanionToolSummary {
    let glyph: DSToolGlyph
    /// The row text, in the tense of where the call is ("Editing Composer.swift").
    let line: String
    /// What it asks permission for ("Edit 3 lines Composer.swift", "Run command").
    let request: String
    /// The shell command, as typed, when the call runs one.
    let command: String?
    /// The command or path, for the approval card and the detail sheet.
    let detail: String?
    let stats: DiffStats?

    init(_ call: ToolCallState) {
        let presentation = ToolPresentation(call)
        glyph = presentation.glyph
        line = Self.sentence(presentation.verb, presentation.subject)
        if case .command(let command) = presentation.body {
            self.command = command
            // A row whose subject is the command itself would say it twice above the command block.
            request = presentation.subjectStyle == .command ? "Run command" : presentation.subject
        } else {
            command = nil
            request = Self.sentence(presentation.verbs?.base, presentation.subject)
        }
        detail = command ?? presentation.subtitle ?? call.locations.first?.path
        stats = presentation.stats
    }

    /// The headline for the detail sheet.
    var subject: String { line }

    private static func sentence(_ verb: String?, _ subject: String) -> String {
        guard let verb, !verb.isEmpty else { return subject }
        return "\(verb.prefix(1).uppercased())\(verb.dropFirst()) \(subject)"
    }
}
