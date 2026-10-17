import SwiftUI

/// A next step the composer offers once a turn ends, such as reviewing or committing the changes
/// it made (docs/product-quality.md: "what to do next"). Features that know about the work (Git,
/// GitHub) provide them through `composerNextSteps`; the app wires them in, so the composer never
/// depends on those features.
struct ComposerNextStep: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let action: @MainActor @Sendable () -> Void
}

extension EnvironmentValues {
    /// Next steps for the session on screen; empty when there's nothing to offer.
    @Entry var composerNextSteps: [ComposerNextStep] = []
}
