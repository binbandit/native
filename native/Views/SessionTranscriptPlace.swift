import SwiftUI

/// Where the user left a session's transcript: the line to bring back, and the anchor that puts it
/// where it was.
///
/// Coming back to a session makes its transcript again, and a new transcript starts at its end. A
/// position (an offset) wouldn't survive that: the lazy stack hasn't measured the rows above the end
/// yet, so the same offset lands on different rows. A line does, and `scrollTo(_:anchor:)` lays out
/// exactly the rows around it, once, with nothing following the scroll afterwards (scroll targets
/// tracked both ways fought the transcript's bottom anchor in a layout loop).
nonisolated struct SessionTranscriptPlace: Equatable {
    let lineID: String
    /// The point of the line that goes to the same point of the view.
    let anchor: UnitPoint
}

/// The places sessions' transcripts were left, for the window: a few bytes per session, held only
/// while its model is in memory, so a session that's removed or closed takes its place with it.
@MainActor
final class SessionTranscriptPlaces {
    private struct Entry {
        weak var session: SessionModel?
        let place: SessionTranscriptPlace
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func place(for session: SessionModel) -> SessionTranscriptPlace? {
        guard let entry = entries[ObjectIdentifier(session)], entry.session === session else { return nil }
        return entry.place
    }

    /// Remembers `place` for `session`; nil when the user left it at its latest output, where it
    /// opens anyway, new output included.
    func remember(_ place: SessionTranscriptPlace?, for session: SessionModel) {
        entries = entries.filter { $0.value.session != nil }
        entries[ObjectIdentifier(session)] = place.map { Entry(session: session, place: $0) }
    }
}

extension EnvironmentValues {
    @Entry var sessionTranscriptPlaces: SessionTranscriptPlaces?
    @Entry fileprivate var sessionTranscriptPlaceTracker: SessionTranscriptPlaceTracker?
}

extension View {
    /// Shows `session`'s transcript where the user left it, when it was left scrolled away from its
    /// latest output. Applied by the transcript to its scrolling content, inside the scroll view; the
    /// lines in it mark themselves with `sessionTranscriptLine(_:)`.
    @ViewBuilder func sessionTranscriptPlace(for session: SessionModel) -> some View {
        if SessionTranscriptPlaceTracker.isEnabled {
            modifier(SessionTranscriptPlaceModifier(session: session))
        } else {
            self
        }
    }

    /// Marks a transcript line by the id its `ForEach` gives it (what `scrollTo` finds it by). Apply
    /// it outermost, so its frame is the one `scrollTo` lines up.
    @ViewBuilder func sessionTranscriptLine(_ id: String) -> some View {
        if SessionTranscriptPlaceTracker.isEnabled {
            modifier(SessionTranscriptLineModifier(id: id))
        } else {
            self
        }
    }
}

private struct SessionTranscriptPlaceModifier: ViewModifier {
    let session: SessionModel
    @Environment(\.sessionTranscriptPlaces) private var places
    @State private var tracker = SessionTranscriptPlaceTracker()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.sessionTranscriptPlaceTracker, tracker)
                .coordinateSpace(.named(SessionTranscriptPlaceTracker.space))
                // Every scroll changes it, so it goes into a reference: following it redraws nothing.
                .onGeometryChange(for: SessionTranscriptViewport.self) { geometry in
                    SessionTranscriptViewport(
                        bounds: geometry.bounds(of: .scrollView(axis: .vertical)),
                        contentHeight: geometry.size.height)
                } action: { [tracker] viewport in
                    tracker.viewport = viewport
                    tracker.restoring = nil
                }
                .onAppear {
                    // A search result opening the session scrolls to it instead.
                    guard session.transcriptReveal == nil, let place = places?.place(for: session) else { return }
                    tracker.restoring = place
                    proxy.scrollTo(place.lineID, anchor: place.anchor)
                }
                .onDisappear {
                    guard case .remember(let place) = tracker.leaving else { return }
                    places?.remember(place, for: session)
                }
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
    /// The place the transcript was brought back to, until a layout has shown it.
    var restoring: SessionTranscriptPlace?

    enum Leaving {
        /// Where it is: a place, or nil at its latest output.
        case remember(SessionTranscriptPlace?)
        /// It went before a layout showed where it was (switching through it quickly), so the place
        /// it came with stands.
        case keep
    }

    /// What to remember as the transcript goes.
    var leaving: Leaving {
        if restoring != nil || viewport == nil { return .keep }
        return .remember(place)
    }

    /// Where the transcript is now; nil at (or near) its latest output.
    private var place: SessionTranscriptPlace? {
        guard let viewport, let bounds = viewport.bounds, bounds.height > 0 else { return nil }
        guard bounds.maxY < viewport.contentHeight - DS.Space.xxxl else { return nil }
        let visible = lineFrames.filter { $0.value.intersects(bounds) }.sorted { $0.value.minY < $1.value.minY }
        // The first line in full view, else the one filling it: its anchor is within the line, so
        // `scrollTo` puts it back exactly.
        let line =
            visible.first { $0.value.minY >= bounds.minY && $0.value.maxY <= bounds.maxY }
            ?? visible.first { $0.value.minY < bounds.minY && $0.value.maxY > bounds.maxY }
        guard let line, abs(bounds.height - line.value.height) > 0.5 else { return nil }
        // `scrollTo` lines the anchor's point in the line up with the same point in the view:
        // offset + anchor * line height = anchor * view height.
        let offset = line.value.minY - bounds.minY
        return SessionTranscriptPlace(
            lineID: line.key, anchor: UnitPoint(x: 0.5, y: offset / (bounds.height - line.value.height)))
    }

    /// Off until verified in the running app: `-sessionTranscriptPlaces YES` (temporary).
    static let isEnabled = UserDefaults.standard.bool(forKey: "sessionTranscriptPlaces")
}
