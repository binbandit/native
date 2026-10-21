import SwiftUI

/// Where the user left a session's transcript: the line to bring back, and the anchor that puts it
/// where it was.
///
/// Coming back to a session makes its transcript again, and a new transcript starts at its end. A
/// position (an offset) wouldn't survive that: the lazy stack hasn't measured the rows above the end
/// yet, so the same offset lands on different rows. A line does: `scrollTo(_:anchor:)` lays out the
/// rows around it and puts it exactly where it was, once, with nothing following the scroll
/// afterwards (scroll targets tracked both ways fought the transcript's bottom anchor in a layout
/// loop, and so does a scroll position held by id).
nonisolated struct SessionTranscriptPlace: Equatable {
    let lineID: String
    /// The point of the line that goes to the same point of the view.
    let anchor: UnitPoint
}

/// Where the user left each session's transcript scrolled, for the window.
/// Entries do not retain sessions or view graphs. Dead entries are
/// pruned when another session is visited; a replacement model starts with a fresh entry.
@MainActor
final class SessionTranscriptMemory {
    private final class Entry {
        weak var session: SessionModel?
        var place: SessionTranscriptPlace?

        init(session: SessionModel) {
            self.session = session
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func place(for session: SessionModel) -> SessionTranscriptPlace? {
        entry(for: session)?.place
    }

    /// Remembers `place` for `session`; nil when the user left it at its latest output, where it
    /// opens anyway, new output included.
    func remember(_ place: SessionTranscriptPlace?, for session: SessionModel) {
        makeEntry(for: session).place = place
    }

    private func entry(for session: SessionModel) -> Entry? {
        guard let entry = entries[ObjectIdentifier(session)], entry.session === session else { return nil }
        return entry
    }

    private func makeEntry(for session: SessionModel) -> Entry {
        if let entry = entry(for: session) { return entry }
        entries = entries.filter { $0.value.session != nil }
        let entry = Entry(session: session)
        entries[ObjectIdentifier(session)] = entry
        return entry
    }
}

extension EnvironmentValues {
    @Entry var sessionTranscriptMemory: SessionTranscriptMemory?
    @Entry fileprivate var sessionTranscriptPlaceTracker: SessionTranscriptPlaceTracker?
}

extension View {
    /// Shows `session`'s transcript where the user left it, when it was left scrolled away from its
    /// latest output. Applied by the transcript to its scrolling content, inside the scroll view; the
    /// lines in it mark themselves with `sessionTranscriptLine(_:)`.
    func sessionTranscriptPlace(for session: SessionModel) -> some View {
        modifier(SessionTranscriptPlaceModifier(session: session))
    }

    /// Marks a transcript line by the id its `ForEach` gives it (what `scrollTo` finds it by). Apply
    /// it outermost, so its frame is the one `scrollTo` lines up.
    func sessionTranscriptLine(_ id: String) -> some View {
        modifier(SessionTranscriptLineModifier(id: id))
    }
}

private struct SessionTranscriptPlaceModifier: ViewModifier {
    let session: SessionModel
    @Environment(\.sessionTranscriptMemory) private var memory
    @State private var tracker = SessionTranscriptPlaceTracker()
    /// Whether the place the transcript came back to is showing, or there was none to bring back.
    @State private var isPlaced = false

    func body(content: Content) -> some View {
        // Laid out but not drawn until it's back in place: a frame of its end first would be a jump.
        let isBringingBack = !isPlaced && session.transcriptReveal == nil && memory?.place(for: session) != nil
        ScrollViewReader { proxy in
            content
                .opacity(isBringingBack ? 0 : 1)
                .accessibilityHidden(isBringingBack)
                .allowsHitTesting(!isBringingBack)
                .environment(\.sessionTranscriptPlaceTracker, tracker)
                .coordinateSpace(.named(SessionTranscriptPlaceTracker.space))
                // Every scroll changes it, so it goes into a reference: following it redraws nothing.
                .onGeometryChange(for: SessionTranscriptViewport.self) { geometry in
                    SessionTranscriptViewport(
                        bounds: geometry.bounds(of: .scrollView(axis: .vertical)),
                        contentHeight: geometry.size.height)
                } action: { [tracker] viewport in
                    tracker.viewport = viewport
                    tracker.layoutChanged()
                }
                .task {
                    // A search result opening the session scrolls to it instead.
                    guard session.transcriptReveal == nil, let place = memory?.place(for: session) else {
                        isPlaced = true
                        return
                    }
                    await tracker.bringBack(place, with: proxy) { isPlaced = true }
                }
                .onChange(of: session.transcriptReveal) { _, request in
                    guard request != nil else { return }
                    tracker.cancelBringingBack()
                    isPlaced = true
                }
                .onDisappear {
                    // A rapid switch can remove the view before its task has even started.
                    if isPlaced, case .remember(let place) = tracker.leaving {
                        memory?.remember(place, for: session)
                    }
                    tracker.cancelBringingBack()
                }
                .animation(nil, value: isPlaced)
        }
    }
}

private struct SessionTranscriptLineModifier: ViewModifier {
    let id: String
    @Environment(\.sessionTranscriptPlaceTracker) private var tracker

    func body(content: Content) -> some View {
        content
            // In the content's coordinates, which scrolling doesn't change: only layout reports.
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named(SessionTranscriptPlaceTracker.space))
            } action: { [tracker, id] frame in
                tracker?.lineFrames[id] = frame
                if tracker?.bringingBack?.place.lineID == id { tracker?.layoutChanged() }
            }
            .onDisappear { [tracker, id] in
                tracker?.lineFrames[id] = nil
            }
    }
}

/// The scroll view's bounds in the transcript content's coordinates, and the content's height.
private nonisolated struct SessionTranscriptViewport: Equatable {
    let bounds: CGRect?
    let contentHeight: CGFloat
}

/// What one transcript shows: the frames of the lines it has made, and the part of it in view.
/// Plain references rather than state, so following them as the user scrolls redraws nothing.
@MainActor
private final class SessionTranscriptPlaceTracker {
    nonisolated static let space = "SessionTranscriptPlace"

    var lineFrames: [String: CGRect] = [:]
    var viewport: SessionTranscriptViewport?

    /// A place being brought back, for the first moments after the transcript appears.
    struct BringingBack {
        let place: SessionTranscriptPlace
        let proxy: ScrollViewProxy
        /// Shows the transcript: once the line is in place, or when time runs out.
        let show: () -> Void
        var scrolls = 0
    }

    private(set) var bringingBack: BringingBack?

    /// Scrolls `place` back into view, and calls `show` once it's there. The scroll view takes no
    /// scrolling while it's first laid out (its initial anchor wins), so the line is scrolled to
    /// after layout until it's in place. Retries are bounded so a removed line cannot keep the
    /// transcript hidden or cause a layout loop. The view's task cancels when the user leaves.
    func bringBack(_ place: SessionTranscriptPlace, with proxy: ScrollViewProxy, show: @escaping () -> Void) async {
        bringingBack = BringingBack(place: place, proxy: proxy, show: show)
        scroll()
        for _ in 0..<15 {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return
            }
            guard bringingBack != nil else { return }
            layoutChanged()
        }
        finishBringingBack()
    }

    func cancelBringingBack() {
        bringingBack = nil
    }

    /// After a layout while bringing a place back: shows the transcript if the line is in place,
    /// and scrolls to it again if not.
    func layoutChanged() {
        guard let bringingBack else { return }
        if let frame = lineFrames[bringingBack.place.lineID], let bounds = viewport?.bounds {
            let wanted = bringingBack.place.anchor.y * (bounds.height - frame.height)
            let offset = frame.minY - bounds.minY
            if abs(offset - wanted) < 0.5 {
                finishBringingBack()
                return
            }
        }
        scroll()
    }

    private func scroll() {
        guard var bringingBack, bringingBack.scrolls < 20 else { return finishBringingBack() }
        bringingBack.scrolls += 1
        self.bringingBack = bringingBack
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            bringingBack.proxy.scrollTo(bringingBack.place.lineID, anchor: bringingBack.place.anchor)
        }
    }

    private func finishBringingBack() {
        let show = bringingBack?.show
        bringingBack = nil
        show?()
    }

    enum Leaving {
        /// Where it is: a place, or nil at its latest output.
        case remember(SessionTranscriptPlace?)
        /// It went before a layout showed where it was (switching through it quickly), so the place
        /// it came with stands.
        case keep
    }

    /// What to remember as the transcript goes.
    var leaving: Leaving {
        if bringingBack != nil || viewport == nil { return .keep }
        return .remember(place)
    }

    /// Where the transcript is now; nil at its latest output.
    private var place: SessionTranscriptPlace? {
        guard let viewport, let bounds = viewport.bounds, bounds.height > 0 else { return nil }
        // The jump button's generous near-end threshold would lose a small but deliberate scroll.
        guard bounds.maxY < viewport.contentHeight - 0.5 else { return nil }
        let visible = lineFrames.filter { $0.value.intersects(bounds) }.sorted { $0.value.minY < $1.value.minY }
        // Prefer a complete line, then one filling the viewport. Two partially visible lines can
        // also fill the screen: an anchor outside the unit square preserves that offset too.
        let line =
            visible.first { $0.value.minY >= bounds.minY && $0.value.maxY <= bounds.maxY }
            ?? visible.first { abs(bounds.height - $0.value.height) > 0.5 }
        guard let line, abs(bounds.height - line.value.height) > 0.5 else { return nil }
        // `scrollTo` lines the anchor's point in the line up with the same point in the view:
        // offset + anchor * line height = anchor * view height.
        let offset = line.value.minY - bounds.minY
        return SessionTranscriptPlace(
            lineID: line.key, anchor: UnitPoint(x: 0.5, y: offset / (bounds.height - line.value.height)))
    }
}
