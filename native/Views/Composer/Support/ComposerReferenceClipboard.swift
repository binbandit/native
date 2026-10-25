import SwiftUI

/// Native clipboard commands receive canonical paths, never the token's display-only line counts.
/// SwiftUI offers these commands on the Mac only; on iPad the text view's own copy and cut apply.
struct ComposerReferenceClipboard: ViewModifier {
    let enabled: Bool
    let copy: () -> [NSItemProvider]
    let cut: () -> [NSItemProvider]

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onCopyCommand(perform: enabled ? copy : nil)
            .onCutCommand(perform: enabled ? cut : nil)
        #else
        content
        #endif
    }
}
