import AppAppearance
import SwiftUI

extension View {
    func companionTranscriptRow(_ id: String) -> some View {
        anchorPreference(key: CompanionTranscriptFrames.self, value: .bounds) { [id: $0] }
    }
}

private struct CompanionTranscriptFrames: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct CompanionTranscriptScrollView<Content: View>: View {
    private let content: Content
    @State private var tracker: CompanionTranscriptPositionTracker

    init(state: CompanionTaskState, @ViewBuilder content: () -> Content) {
        self.content = content()
        _tracker = State(initialValue: CompanionTranscriptPositionTracker(state: state))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .overlay(alignment: .bottom) {
                        Color.clear.frame(height: 0).id(CompanionTranscriptPositionTracker.bottomID)
                    }
                    .backgroundPreferenceValue(CompanionTranscriptFrames.self) { anchors in
                        GeometryReader { geometry in
                            // Resolve all anchors with one proxy. Independent row callbacks can pair
                            // new-width frames with the old viewport during a fold.
                            let layout = TranscriptReadingPosition.Layout(
                                viewport: geometry.bounds(of: .scrollView(axis: .vertical)) ?? .zero,
                                contentHeight: geometry.size.height,
                                rows: anchors.mapValues { geometry[$0] })
                            Color.clear.onChange(of: layout, initial: true) { _, layout in
                                tracker.observe(layout, with: proxy)
                            }
                        }
                    }
            }
            .defaultScrollAnchor(.bottom)
            .onScrollPhaseChange { _, phase in
                if phase != .idle {
                    tracker.userDidScroll()
                }
            }
            .onAppear { tracker.appear() }
            .onDisappear { tracker.disappear() }
        }
    }
}

/// Geometry is deliberately not observable: remembering a scroll should not redraw the task.
@MainActor
private final class CompanionTranscriptPositionTracker {
    static let bottomID = "companion-transcript-bottom"
    private let state: CompanionTaskState
    private var position: TranscriptReadingPosition
    private var restoration: Task<Void, Never>?
    private var isVisible = true

    init(state: CompanionTaskState) {
        self.state = state
        position = TranscriptReadingPosition(place: state.transcriptPlace)
    }

    func appear() {
        if !isVisible { position = TranscriptReadingPosition(place: state.transcriptPlace) }
        isVisible = true
    }

    func disappear() {
        isVisible = false
        restoration?.cancel()
        restoration = nil
        position.detach()
        // The last complete layout already saved the passage, before lazy rows disappeared.
    }

    func userDidScroll() {
        restoration?.cancel()
        restoration = nil
        position.userDidScroll()
    }

    func observe(_ layout: TranscriptReadingPosition.Layout, with proxy: ScrollViewProxy) {
        guard isVisible else { return }
        let resized = position.layout?.viewport.size != layout.viewport.size
        let targetArrived =
            position.place.map {
                position.layout?.rows[$0.id] == nil && layout.rows[$0.id] != nil
            } ?? false
        position.update(layout)
        // Loading history may finish after the bounded initial attempt has ended.
        if resized || targetArrived {
            restoration?.cancel()
            restoration = nil
        }
        guard position.isRestoring else {
            state.transcriptPlace = position.place
            return
        }
        guard restoration == nil else { return }
        restoration = Task { [weak self] in
            // A lazy stack can ignore the first request while its initial bottom anchor wins.
            // Bound retries, and never hide the transcript if a row has gone away.
            for _ in 0..<20 {
                guard let self, !Task.isCancelled, isVisible, position.isRestoring else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if let place = position.place {
                        proxy.scrollTo(place.id, anchor: UnitPoint(x: 0.5, y: place.anchorY))
                    } else {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
            }
        }
    }
}

#if DEBUG
#Preview("Transcript - Folding companion") {
    DSPreviewPair {
        CompanionLayoutPreview()
            .frame(width: 760, height: 700)
    }
}
#endif
