import SwiftUI

/// Cut supplies canonical text to the pasteboard itself, so it also records the inverse edit.
@MainActor
final class ComposerEditorUndo {
    private let text: Binding<String>
    private let value: String

    private init(text: Binding<String>) { self.text = text; value = text.wrappedValue }

    static func record(_ text: Binding<String>, using manager: UndoManager?) {
        guard let manager else { return }
        let target = ComposerEditorUndo(text: text)
        manager.registerUndo(withTarget: target) { [target, weak manager] _ in
            MainActor.assumeIsolated {
                record(target.text, using: manager)
                target.text.wrappedValue = target.value
            }
        }
        manager.setActionName("Cut")
    }
}
