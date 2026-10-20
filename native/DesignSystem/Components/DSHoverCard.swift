import SwiftUI

/// A hover card's state: it opens once the pointer has rested on its anchor for `openDelay`, like a
/// tooltip, stays while the pointer is on the anchor or the card, and closes `closeDelay` after it
/// leaves both, so the pointer can cross the gap into the card. While one shows, or right after,
/// the next opens almost at once, so moving along a column of anchors reads each without waiting.
/// Only one shows at a time. Owned by the anchor's view (`@State`) and presented with `.dsHoverCard(_:)`; where
/// there's no pointer (touch), the anchor's tap calls `toggle()`.
@MainActor
@Observable
public final class DSHoverCardState {
    public var isPresented = false {
        didSet {
            guard isPresented != oldValue else { return }
            if isPresented {
                if Self.shown !== self { Self.shown?.close() }
                Self.shown = self
            } else {
                // A click outside closes the popover without a hover exit.
                isOnCard = false
                pending?.cancel()
                if Self.shown === self { Self.shown = nil }
            }
        }
    }

    /// How long the pointer rests on the anchor before the card opens.
    public static let openDelay: Duration = .milliseconds(500)
    /// How long the card waits for the pointer to come back before closing.
    public static let closeDelay: Duration = .milliseconds(200)
    /// The rest needed while another card shows or just closed: enough to pass over an anchor
    /// without opening its card.
    private static let warmOpenDelay: Duration = .milliseconds(100)
    /// How long after one card closes the next still opens warm.
    private static let warmWindow: TimeInterval = 0.6

    private static weak var shown: DSHoverCardState?
    private static var cooledAt: Date = .distantPast

    @ObservationIgnored private var isOnAnchor = false
    @ObservationIgnored private var isOnCard = false
    /// Set by `dismiss()`: the card stays closed until the pointer leaves the anchor.
    @ObservationIgnored private var isSuppressed = false
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init() {}

    /// Closes it now, after the anchor's own action (a click that navigates), and keeps it closed
    /// while the pointer stays.
    public func dismiss() {
        isSuppressed = isOnAnchor
        close()
    }

    /// Opens or closes it now: the anchor's tap where there's no hover.
    public func toggle() {
        pending?.cancel()
        isPresented.toggle()
    }

    func pointerOnAnchor(_ isOn: Bool) {
        isOnAnchor = isOn
        if !isOn { isSuppressed = false }
        schedule()
    }

    func pointerOnCard(_ isOn: Bool) {
        isOnCard = isOn
        schedule()
    }

    func anchorDisappeared() {
        isOnAnchor = false
        close()
    }

    private func close() {
        pending?.cancel()
        isPresented = false
    }

    private func schedule() {
        pending?.cancel()
        let wanted = (isOnAnchor && !isSuppressed) || (isPresented && isOnCard)
        guard wanted != isPresented else { return }
        let isWarm = Self.shown != nil || Date.now.timeIntervalSince(Self.cooledAt) < Self.warmWindow
        let delay = wanted ? (isWarm ? Self.warmOpenDelay : Self.openDelay) : Self.closeDelay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            if !wanted { Self.cooledAt = .now }
            isPresented = wanted
        }
    }
}

extension View {
    /// Shows `content` in the design system's popover when the pointer rests on this view, as
    /// `DSHoverCardState` describes: details that would crowd the view itself, with actions the
    /// pointer can move in and click. Everything in the card must also be reachable without hover
    /// (a context menu, a command), and on touch the anchor's tap opens it.
    public func dsHoverCard(
        _ state: DSHoverCardState,
        arrowEdge: Edge = .trailing,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(DSHoverCardModifier(state: state, arrowEdge: arrowEdge, card: content))
    }
}

private struct DSHoverCardModifier<Card: View>: ViewModifier {
    @Bindable var state: DSHoverCardState
    let arrowEdge: Edge
    let card: () -> Card

    func body(content: Content) -> some View {
        content
            .onHover { state.pointerOnAnchor($0) }
            .onDisappear { state.anchorDisappeared() }
            .dsPopover(isPresented: $state.isPresented, arrowEdge: arrowEdge) {
                card()
                    .onHover { state.pointerOnCard($0) }
            }
    }
}
