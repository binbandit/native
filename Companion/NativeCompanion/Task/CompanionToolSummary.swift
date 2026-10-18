import ACP
import Foundation

/// A tool call in one line for the phone, in the Mac's own words: `ToolPresentation` (shared from
/// the Mac's transcript) decides the symbol, verb and subject, so a task reads the same on both.
struct CompanionToolSummary {
    let symbol: String
    /// The row text, in the tense of where the call is ("Editing Composer.swift").
    let line: String
    /// What it asks permission for ("Run pnpm test").
    let request: String
    /// The command or path, for the approval card and the detail sheet.
    let detail: String?
    let stats: DiffStats?

    init(_ call: ToolCallState) {
        var presentation = ToolPresentation(call)
        presentation.phase = ToolPhase(call)
        symbol = presentation.symbol
        line = Self.sentence(presentation.verb, presentation.subject)
        request = Self.sentence(presentation.verbs?.base, presentation.subject)
        detail = call.rawInput?["command"]?.stringValue ?? presentation.subtitle ?? call.locations.first?.path
        stats = presentation.stats
    }

    /// The headline for the detail sheet.
    var subject: String { line }

    private static func sentence(_ verb: String?, _ subject: String) -> String {
        guard let verb, !verb.isEmpty else { return subject }
        return "\(verb.prefix(1).uppercased())\(verb.dropFirst()) \(subject)"
    }
}
