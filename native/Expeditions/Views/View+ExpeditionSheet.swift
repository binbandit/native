import SwiftUI

extension View {
    /// The New Expedition sheet, presented when something asks for it (the menu, the page); a new
    /// expedition opens on the Expeditions page.
    func newExpeditionSheet() -> some View {
        modifier(NewExpeditionSheetModifier())
    }
}

private struct NewExpeditionSheetModifier: ViewModifier {
    @Environment(ExpeditionCenter.self) private var center

    func body(content: Content) -> some View {
        @Bindable var center = center
        content.sheet(isPresented: $center.isNewExpeditionRequested) {
            NewExpeditionSheet { center.show($0) }
        }
    }
}
