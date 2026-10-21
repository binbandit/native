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
    /// The current command shortcut, resolved when the fact is rendered so remapping stays current.
    var help: (@MainActor (_ isOpen: Bool) -> String)?
    /// Review and Commit actions for the transcript's files-changed card.
    var turnChanges: (@MainActor (SessionToolContext) -> TurnChangesActions)?
    /// Called when the user closes the tool, not when resizing moves its pane to another container.
    var didClose: @MainActor (SessionToolContext) -> Void = { _ in }

    var id: SessionToolID { spec.id }
}
