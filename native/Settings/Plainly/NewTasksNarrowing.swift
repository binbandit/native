import SwiftUI

/// One rule for every New Tasks row as the page narrows: source tags shrink to their glyph first,
/// and only past that does every value move under its label, so a group never mixes layouts.
struct NewTasksNarrowing: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .environment(\.newTasksCompactSources, width < DS.Settings.compactSourcesBelow)
            .environment(\.settingsControlBelow, width < DS.Settings.stackedRowsBelow)
    }
}
