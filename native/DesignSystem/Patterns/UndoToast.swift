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
    /// dismisses it, or `duration` passes (the reference app's toasts: bottom right, 5 seconds). Setting a
    /// new item replaces the current one.
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
        HStack(spacing: DS.Space.md) {
            Text(message)
                .font(.dsCallout)
                .tracking(DS.Tracking.tight)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(2)
            Spacer(minLength: DS.Space.md)
            Button("Undo", action: onUndo)
                .buttonStyle(.ds(.secondary))
            IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
        }
        .padding(.leading, DS.Space.xl)
        .padding(.trailing, DS.Space.md)
        .padding(.vertical, DS.Space.md)
        .frame(width: 356)
        .dsOverlayBackground(in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .dsShadow(.modal)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview("Undo toast") {
    DSPreviewPair {
        UndoToast(message: "Archived “Sidebar polish”", onUndo: {}, onDismiss: {})
    }
}
