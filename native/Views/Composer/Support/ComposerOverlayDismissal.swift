import SwiftUI

/// A screen overlay takes Escape before the editor's own suggestions, attachments or Stop action.
/// The host supplies a model action, so the composer does not need to know which feature is open.
struct ComposerOverlayDismissal {
    let dismiss: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var composerOverlayDismissal: ComposerOverlayDismissal?
}
