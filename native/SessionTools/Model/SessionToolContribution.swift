import SessionTools
import SwiftUI

/// A tool a feature adds to the session screen, the lean-core plan's session panel: where it can
/// live, what it says about the task under the title, and its pane. Features register theirs with
/// `SessionToolRegistry`, and the session screen reads tools only from there, so a tool that isn't
/// registered (or is off) leaves nothing behind.
struct SessionToolContribution: Identifiable {
    let spec: SessionToolSpec
    let title: String
    let systemImage: String
    /// What it says about the task now; nil while it has nothing to say, which hides its fact.
    var fact: @MainActor (SessionToolContext) -> SessionToolFact? = { _ in nil }
    /// Whether its pane has something in it now (changes made, a shell open), which keeps its tab.
    var hasContent: @MainActor (SessionToolContext) -> Bool = { _ in false }
    /// Its pane; nil for a tool that acts rather than shows (Open In).
    var pane: (@MainActor (SessionToolContext) -> AnyView)?
    /// What clicking its fact does when it has no pane.
    var perform: @MainActor (SessionToolContext) -> Void = { _ in }
    /// Its fact's menu (a secondary click, or touch and hold): Open In's other apps.
    var menu: (@MainActor (SessionToolContext) -> AnyView)?
    /// What it does for the transcript's own controls: the files-changed card, a subagent's card.
    var transcript: (@MainActor (SessionToolContext) -> SessionTranscriptActions)?
    /// Its own tabs in a place's strip, for a tool that's several things at once (the terminal's
    /// shells and runs); nil shows the tool as one tab.
    var tabs: (@MainActor (SessionToolContext) -> [SessionToolTabItem])?
    /// Adds one more of its tabs (a new shell), offered as + after them.
    var newTab: (@MainActor (SessionToolContext) -> Void)?
    /// Shown at the strip's trailing end while the tool is open (a run's time and Stop).
    var stripAccessory: (@MainActor (SessionToolContext) -> AnyView?)?
    /// A view with nothing to see that the tool keeps on the screen while it's on, to keep its own
    /// state in step with the screen's (the terminal's colors, and ⌃` showing it).
    var companion: (@MainActor (SessionToolContext) -> AnyView)?

    var id: SessionToolID { spec.id }
}
