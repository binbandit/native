import SwiftUI

/// Something the user just did that can be taken back, shown as a toast with an Undo button.
/// Prefer this to a confirmation dialog: act at once, offer the undo.
public struct UndoToastItem: Identifiable, Equatable {
    public let id = UUID()
    /// What just happened: "Archived “Sidebar polish”".
    public let message: String
    let undo: () -> Void

    public init(_ message: String, undo: @escaping () -> Void) {
        self.message = message
        self.undo = undo
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    /// Shows `item` as an undo toast at the bottom trailing corner until the user undoes it,
    /// dismisses it, or `duration` passes. Setting a new item replaces the current one. Put it on
    /// the content the toast belongs to, above any status bar, so it never covers the window's chrome.
    public func undoToast(_ item: Binding<UndoToastItem?>, duration: Duration = .seconds(5)) -> some View {
        modifier(UndoToastPresenter(item: item, duration: duration))
    }
}

private struct UndoToastPresenter: ViewModifier {
    @Binding var item: UndoToastItem?
    let duration: Duration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if let current = item {
                    UndoToast(message: current.message) {
                        current.undo()
                        item = nil
                    } onDismiss: {
                        item = nil
                    }
                    .padding(DS.Space.xxl)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: current.id) {
                        // Said rather than focused: the toast leaves on its own, and moving VoiceOver
                        // into it would pull the user away from what they were doing.
                        AccessibilityNotification.Announcement(current.message).post()
                        try? await Task.sleep(for: duration)
                        if item?.id == current.id {
                            item = nil
                        }
                    }
                }
            }
            .animation(.dsPanel, value: item)
    }
}

/// The toast itself: the message, Undo, and a dismiss button, on an overlay surface.
public struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    public init(message: String, onUndo: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        // The message is set like Undo's label and shares its baseline, so a one-line message sits
        // level with the buttons and a longer one wraps beneath them.
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.lg) {
            Text(message)
                .font(.dsBody)
                .tracking(DS.Tracking.tight)
                .foregroundStyle(.dsTextPrimary)
                // Room for what was done and what was kept ("…saving uncommitted work as a checkpoint")
                // without cutting off the part that reassures.
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                // A line as tall as the buttons, so the margins stay even however many lines wrap.
                .padding(.vertical, DS.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.xs) {
                Button("Undo", action: onUndo)
                    .buttonStyle(.ds(.secondary))
                IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
                    // Its glyph has a baseline of its own; Undo's label sets the row's.
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            }
        }
        .padding(.leading, DS.Space.xl)
        .padding(.trailing, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .frame(width: 356)
        .dsOverlayBackground(in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .dsShadow(.modal)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Undo toast") {
    DSPreviewPair {
        UndoToast(message: "Archived “Sidebar polish”", onUndo: {}, onDismiss: {})
        UndoToast(
            message:
                "Archived “Sidebar polish”. Removed its worktree and branch, saving uncommitted work as a checkpoint.",
            onUndo: {}, onDismiss: {})
    }
}
