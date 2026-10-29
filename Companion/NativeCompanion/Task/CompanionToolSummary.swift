import ACP
import Foundation

/// A tool call in one line for the phone, in the Mac's own words: the shared wording
/// (`ToolCallWording`, through `ToolPresentation`) decides the glyph and the sentence, so a task
/// reads the same on both.
struct CompanionToolSummary {
    let glyph: DSToolGlyph
    /// The row text, in the tense of where the call is ("Editing Composer.swift").
    let line: String
    /// What it asks permission for ("Edit Composer.swift", "Run command").
    let request: String
    /// The shell command, as typed, when the call runs one.
    let command: String?
    /// The command or path, for the approval card and the detail sheet.
    let detail: String?
    let stats: DiffStats?

    init(_ call: ToolCallState) {
        let presentation = ToolPresentation(call)
        glyph = presentation.glyph
        line = presentation.sentence
        if case .command(let command) = presentation.body {
            self.command = command
            // The approval card shows the command itself under this.
            request = "Run command"
        } else {
            command = nil
            request = presentation.request
        }
        detail = command ?? presentation.wording.detail ?? call.locations.first?.path
        stats = presentation.stats
    }

    /// The headline for the detail sheet.
    var subject: String { line }
}
