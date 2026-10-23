import SwiftUI

/// A row search jumped to. Each jump is distinct, so picking the same result again flashes again.
struct SettingsReveal: Equatable {
    let rowID: SettingsRowID
    let nonce = UUID()
}

extension EnvironmentValues {
    /// The row that should flash, once the page has scrolled to it.
    @Entry var settingsScrollTo: (SettingsRowID, UnitPoint) -> Void = { _, _ in }

    @Entry var settingsFlash: SettingsReveal?
}

extension View {
    /// Makes the view a search target: the page can scroll to it, and it flashes when revealed.
    func settingsRevealTarget(_ id: SettingsRowID?) -> some View {
        modifier(SettingsRevealModifier(rowID: id))
    }
}

/// The reveal: a 2pt ring 8pt outside the row that holds for 55% of 1.4s, then fades.
private struct SettingsRevealModifier: ViewModifier {
    let rowID: SettingsRowID?

    @Environment(\.settingsFlash) private var flash
    @Environment(\.settingsPlainly) private var plainly
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringOpacity = 0.0

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: plainly ? DS.Radius.card : 0)
                    .strokeBorder(.dsTextSecondary, lineWidth: SettingsMetrics.revealRingWidth)
                    .padding(-SettingsMetrics.revealRingOutset)
                    .opacity(ringOpacity)
                    .allowsHitTesting(false)
            }
            .id(rowID)
            .task(id: flash) {
                guard let flash, flash.rowID == rowID else { return }
                ringOpacity = 1
                try? await Task.sleep(for: .milliseconds(770))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.63)) {
                    ringOpacity = 0
                }
            }
    }
}
