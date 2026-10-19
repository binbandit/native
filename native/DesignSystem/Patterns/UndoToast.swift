import Observation
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
    /// Inside an `undoToastAnchor()` the toast shows at the anchor instead.
    public func undoToast(_ item: Binding<UndoToastItem?>, duration: Duration = .seconds(5)) -> some View {
        modifier(UndoToastPresenter(item: item, duration: duration))
    }

    /// Shows the undo toasts raised inside this view at its bottom trailing corner, rather than at
    /// the bottom of whatever raised them. Put it on a pane whose content scrolls, outside the scroll
    /// view, so a toast shows where the user is looking however long the content is. The newest toast
    /// raised inside replaces the one showing.
    public func undoToastAnchor() -> some View {
        modifier(UndoToastAnchor())
    }
}

/// The toast showing at an `undoToastAnchor()`, with what clears the binding that raised it.
@Observable
final class UndoToastAnchorSlot {
    struct Request {
        let item: UndoToastItem
        let duration: Duration
        let clear: () -> Void
    }

    var request: Request?
}

nonisolated extension EnvironmentValues {
    /// The anchor that undo toasts raised here show at, if any.
    @Entry var undoToastAnchor: UndoToastAnchorSlot?
}

private struct UndoToastPresenter: ViewModifier {
    @Binding var item: UndoToastItem?
    let duration: Duration

    @Environment(\.undoToastAnchor) private var anchor

    func body(content: Content) -> some View {
        if let anchor {
            content.onChange(of: item?.id, initial: true) { old, _ in
                if let item {
                    let binding = $item
                    anchor.request = .init(item: item, duration: duration) {
                        if binding.wrappedValue?.id == item.id { binding.wrappedValue = nil }
                    }
                } else if let old, anchor.request?.item.id == old {
                    // Taken back by whatever raised it.
                    anchor.request = nil
                }
            }
        } else {
            content.overlay(alignment: .bottomTrailing) {
                UndoToastSlot(item: item, duration: duration) { id in
                    if item?.id == id { item = nil }
                }
            }
        }
    }
}

private struct UndoToastAnchor: ViewModifier {
    @State private var slot = UndoToastAnchorSlot()

    func body(content: Content) -> some View {
        content
            .environment(\.undoToastAnchor, slot)
            .overlay(alignment: .bottomTrailing) {
                UndoToastSlot(item: slot.request?.item, duration: slot.request?.duration ?? .zero) { id in
                    guard let request = slot.request, request.item.id == id else { return }
                    slot.request = nil
                    request.clear()
                }
            }
    }
}

/// A toast in its corner: it slides in, and leaves when undone, dismissed or after `duration`.
/// `clear` gets the id of the toast that's done, so one that has since replaced it stays.
private struct UndoToastSlot: View {
    let item: UndoToastItem?
    let duration: Duration
    let clear: (UndoToastItem.ID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let current = item {
                UndoToast(message: current.message) {
                    current.undo()
                    clear(current.id)
                } onDismiss: {
                    clear(current.id)
                }
                .padding(DS.Space.xxl)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: current.id) {
                    // Said rather than focused: the toast leaves on its own, and moving VoiceOver
                    // into it would pull the user away from what they were doing.
                    AccessibilityNotification.Announcement(current.message).post()
                    guard (try? await Task.sleep(for: duration)) != nil else { return }
                    clear(current.id)
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
