import SwiftUI

/// An undo offer whose trailing edge is its primary action.
public struct UndoToast: View {
    let message: String
    let undoesWithCommandZ: Bool
    let onUndo: () -> Void
    let onDismiss: () -> Void
    var onHoldChanged: (Bool) -> Void = { _ in }

    @State private var isHovered = false
    @State private var undoIsHovered = false
    @State private var closeIsHovered = false
    @FocusState private var focus: Control?
    #if DEBUG
    var previewState: UndoToastPreviewState = .rest
    #endif

    private enum Control: Hashable { case undo, dismiss }

    public init(
        message: String, undoesWithCommandZ: Bool = false,
        onUndo: @escaping () -> Void, onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.undoesWithCommandZ = undoesWithCommandZ
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: 0) {
            Text(message)
                .font(.dsBody)
                .tracking(DS.Tracking.tight)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, DS.Space.xl)
                .padding([.trailing, .vertical], DS.Space.lg)
            Rectangle().fill(.dsSeparator).frame(width: 1)
            undoButton
        }
        .frame(width: 356)
        .frame(minHeight: 40)
        .fixedSize(horizontal: false, vertical: true)
        .dsOverlayBackground(in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1).allowsHitTesting(false) }
        .dsShadow(.modal)
        .overlay(alignment: .topLeading) { closeButton.offset(x: -7, y: -7) }
        // Include the corner close in hover tracking so reaching for it never restarts dismissal.
        .padding([.top, .leading], 7)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .padding([.top, .leading], -7)
        .onChange(of: isHeld) { _, held in onHoldChanged(held) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityAction(named: "Undo", onUndo)
        .accessibilityAction(named: "Dismiss", onDismiss)
        .simultaneousGesture(
            DragGesture().onEnded { value in
                if DS.isTouchPlatform, value.translation.height > DS.Space.xxl,
                    value.translation.height > abs(value.translation.width)
                {
                    onDismiss()
                }
            }, including: DS.isTouchPlatform ? .all : .none)
    }

    private var isHeld: Bool { isHovered || focus != nil }

    private var showsClose: Bool {
        #if DEBUG
        if previewState.showsClose { return true }
        #endif
        return DS.isTouchPlatform || isHeld
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            HStack(spacing: DS.Space.sm) {
                Text("Undo").font(.dsBodyMedium).tracking(DS.Tracking.tight)
                if undoesWithCommandZ { Kbd("⌘Z", style: .plain) }
            }
            .foregroundStyle(.dsTextPrimary)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .contentShape(undoShape)
            .dsHitTarget(40)
        }
        .buttonStyle(UndoToastEdgeStyle(isHovered: undoIsHovered, preview: previewInteraction))
        .fixedSize(horizontal: true, vertical: false)
        .focused($focus, equals: .undo)
        .trackHover($undoIsHovered)
        .accessibilityLabel("Undo")
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(closeIsHovered ? .dsTextPrimary : .dsTextSecondary)
                .frame(width: 18, height: 18)
                .background(.dsSurfaceRaised, in: Circle())
                .overlay { Circle().strokeBorder(.dsBorder, lineWidth: 1) }
                .dsShadow(.drag)
                .contentShape(.circle)
                .dsHitTarget(18)
        }
        .buttonStyle(.plain)
        .dsFocusShape(Circle())
        .focused($focus, equals: .dismiss)
        .trackHover($closeIsHovered)
        .opacity(showsClose ? 1 : 0)
        .allowsHitTesting(showsClose)
        .animation(.dsQuick, value: showsClose)
        .accessibilityLabel("Dismiss")
        .help("Dismiss")
    }

    private var previewInteraction: UndoToastEdgeStyle.Interaction {
        #if DEBUG
        switch previewState {
        case .hover: return .hover
        case .pressed: return .pressed
        case .focus: return .focus
        default: break
        }
        #endif
        return .rest
    }

    private var undoShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomTrailingRadius: DS.Radius.card, topTrailingRadius: DS.Radius.card)
    }
}

private struct UndoToastEdgeStyle: ButtonStyle {
    enum Interaction { case rest, hover, pressed, focus }
    let isHovered: Bool
    let preview: Interaction

    func makeBody(configuration: Configuration) -> some View {
        let shape = UnevenRoundedRectangle(
            bottomTrailingRadius: DS.Radius.card, topTrailingRadius: DS.Radius.card)
        configuration.label
            .background(
                configuration.isPressed || preview == .pressed
                    ? .dsPressed : isHovered || preview == .hover ? .dsHover : .clear, in: shape
            )
            .dsFocusShape(shape)
            .overlay {
                if preview == .focus {
                    shape.strokeBorder(.dsAccent.opacity(0.5), lineWidth: 3)
                }
            }
    }
}
