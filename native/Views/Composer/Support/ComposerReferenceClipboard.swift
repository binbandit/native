import SwiftUI

/// Native clipboard commands receive canonical paths, never the token's display-only line counts.
struct ComposerReferenceClipboard: ViewModifier {
    let enabled: Bool
    let copy: () -> [NSItemProvider]
    let cut: () -> [NSItemProvider]

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.onCopyCommand(perform: enabled ? copy : nil)
                .onCutCommand(perform: enabled ? cut : nil)
        } else {
            content
        }
    }
}
