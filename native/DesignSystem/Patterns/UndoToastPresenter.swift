import Observation
import SwiftUI
import Undo

/// Something the user just did that can be taken back, shown as a toast with an Undo button.
/// Prefer this to a confirmation dialog: act at once, offer the undo.
public struct UndoToastItem: Identifiable, Equatable {
    public let id = UUID()
    /// What just happened: "Archived “Sidebar polish”".
    public let message: String
    public var undoesWithCommandZ: Bool
    let undo: () -> Void

    public init(_ message: String, undoesWithCommandZ: Bool = false, undo: @escaping () -> Void) {
        self.message = message
        self.undoesWithCommandZ = undoesWithCommandZ
        self.undo = undo
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.undoesWithCommandZ == rhs.undoesWithCommandZ
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
        var item: UndoToastItem
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
            .onChange(of: item?.undoesWithCommandZ) {
                if let item, anchor.request?.item.id == item.id {
                    anchor.request?.item = item
                }
            }
        } else {
            content.overlayPreferenceValue(UndoToastBottomInset.self) { inset in
                UndoToastSlot(item: item, duration: duration, bottomInset: inset) { id in
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
            .overlayPreferenceValue(UndoToastBottomInset.self) { inset in
                UndoToastSlot(item: slot.request?.item, duration: slot.request?.duration ?? .zero, bottomInset: inset) {
                    id in
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
    let bottomInset: CGFloat
    let clear: (UndoToastItem.ID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let current = item {
                UndoToastPresentation(item: current, duration: duration) { clear(current.id) }
                    .id(current.id)
                    .padding([.top, .horizontal], DS.Space.xxl)
                    // The measured bar already includes the composer's bottom margin.
                    .padding(.bottom, max(DS.Space.xxl, bottomInset + DS.Space.lg))
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .offset(y: DS.Space.xs).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.dsPanel, value: item)
    }
}

/// Each offer owns its lifetime so replacement cancels the old timer without touching the new one.
private struct UndoToastPresentation: View {
    let item: UndoToastItem
    let clear: () -> Void
    @State private var lifetime: UndoToastLifetime

    init(item: UndoToastItem, duration: Duration, clear: @escaping () -> Void) {
        self.item = item
        self.clear = clear
        _lifetime = State(initialValue: UndoToastLifetime(duration: duration))
    }

    var body: some View {
        var toast = UndoToast(message: item.message, undoesWithCommandZ: item.undoesWithCommandZ) {
            item.undo()
            clear()
        } onDismiss: {
            clear()
        }
        toast.onHoldChanged = { lifetime.setHeld($0) }
        return
            toast
            .task {
                // Announce without moving VoiceOver away from the user's work.
                AccessibilityNotification.Announcement(item.message).post()
            }
            .task(id: lifetime.deadline) {
                guard let deadline = lifetime.deadline else { return }
                do {
                    try await Task.sleep(until: deadline, clock: .continuous)
                    try Task.checkCancellation()
                    guard lifetime.deadline == deadline else { return }
                    clear()
                } catch {}
            }
    }
}
