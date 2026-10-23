import SwiftUI

#if DEBUG
/// Inert interaction states share the production toast layout and button style.
enum UndoToastPreviewState: String, CaseIterable {
    case rest = "Rest"
    case hover = "Hover"
    case pressed = "Pressed"
    case focus = "Keyboard focus"
    case oneLine = "One line"
    case withoutShortcut = "Without ⌘Z"
    case threeLines = "Three lines"
    case touch = "iPad"

    var message: String {
        switch self {
        case .oneLine: "Pinned “Queue follow-ups while a turn runs”."
        case .withoutShortcut: "Conversation resolved"
        case .threeLines:
            "Archived “Sidebar polish”. Removed its worktree and branch, saving uncommitted work as a checkpoint."
        default: "Archived “Wrap diff lines at word boundaries”. Removed its worktree."
        }
    }

    var showsClose: Bool { self == .hover || self == .pressed || self == .focus || self == .touch }

    var toast: UndoToast {
        var toast = UndoToast(
            message: message, undoesWithCommandZ: self != .withoutShortcut, onUndo: {}, onDismiss: {})
        toast.previewState = self
        return toast
    }
}

struct UndoToastPreviewGallery: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(UndoToastPreviewState.allCases, id: \.self) { state in
                DSPreviewPair {
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        Text(state.rawValue).font(.dsBody).foregroundStyle(.dsTextSecondary)
                        state.toast
                        Spacer(minLength: 0)
                    }
                    .frame(width: 356, height: 80, alignment: .topLeading)
                }
            }
        }
    }
}

#Preview("Undo toast - Rest") { DSPreviewPair { UndoToastPreviewState.rest.toast } }
#Preview("Undo toast - Hover") { DSPreviewPair { UndoToastPreviewState.hover.toast } }
#Preview("Undo toast - Pressed") { DSPreviewPair { UndoToastPreviewState.pressed.toast } }
#Preview("Undo toast - Keyboard focus") { DSPreviewPair { UndoToastPreviewState.focus.toast } }
#Preview("Undo toast - One line") { DSPreviewPair { UndoToastPreviewState.oneLine.toast } }
#Preview("Undo toast - Without shortcut") { DSPreviewPair { UndoToastPreviewState.withoutShortcut.toast } }
#Preview("Undo toast - Three lines") { DSPreviewPair { UndoToastPreviewState.threeLines.toast } }
#Preview("Undo toast - iPad") { DSPreviewPair { UndoToastPreviewState.touch.toast } }
#endif
