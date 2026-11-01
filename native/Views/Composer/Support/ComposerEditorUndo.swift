import SwiftUI

/// Binding edits bypass the text view's undo transaction, so they record their inverse explicitly.
@MainActor
final class ComposerEditorUndo {
    private let text: Binding<String>
    private let value: String

    private init(text: Binding<String>) { self.text = text; value = text.wrappedValue }

    static func record(_ text: Binding<String>, using manager: UndoManager?, actionName: String = "Cut") {
        guard let manager else { return }
        let target = ComposerEditorUndo(text: text)
        manager.registerUndo(withTarget: target) { [target, weak manager] _ in
            MainActor.assumeIsolated {
                record(target.text, using: manager, actionName: actionName)
                target.text.wrappedValue = target.value
            }
        }
        manager.setActionName(actionName)
    }
}
