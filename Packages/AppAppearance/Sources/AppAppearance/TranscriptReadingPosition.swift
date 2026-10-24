import CoreGraphics
import Foundation

/// A measured passage, retained independently of the scroll view that currently displays it.
/// Layouts must contain row frames and viewport bounds from the same coordinate space and pass.
public struct TranscriptReadingPosition: Sendable {
    public struct Place: Equatable, Sendable {
        public let id: String
        public let anchorY: CGFloat

        public init(id: String, anchorY: CGFloat) {
            self.id = id
            self.anchorY = anchorY
        }
    }

    public struct Layout: Equatable, Sendable {
        public let viewport: CGRect
        public let contentHeight: CGFloat
        public let rows: [String: CGRect]

        public init(viewport: CGRect, contentHeight: CGFloat, rows: [String: CGRect]) {
            self.viewport = viewport
            self.contentHeight = contentHeight
            self.rows = rows
        }

        fileprivate var isValid: Bool {
            viewport.width > 0 && viewport.height > 0 && contentHeight > 0
                && viewport.minY.isFinite && viewport.width.isFinite && viewport.height.isFinite
                && contentHeight.isFinite
        }

        fileprivate var isAtLatest: Bool { viewport.maxY >= contentHeight - 0.5 }
    }

    /// Nil means the latest output, including output that arrives while the view is absent.
    public private(set) var place: Place?
    public private(set) var isRestoring = true
    public private(set) var layout: Layout?
    private var awaitingMissingRow = false
    private var isUserScrolling = false

    public init(place: Place? = nil) {
        self.place = place
    }

    public mutating func update(_ next: Layout) {
        guard next.isValid else { return }
        // Freeze the old passage before examining any rows at the new width or height.
        if layout?.viewport.size != next.viewport.size {
            isRestoring = true
            isUserScrolling = false
        }
        layout = next
        if awaitingMissingRow {
            guard let place, next.rows[place.id] != nil else { return }
            awaitingMissingRow = false
            isRestoring = true
        }
        // A resize can report an aligned viewport before the lazy content has reflowed.
        // Keep the target through those intermediate passes until restoration finishes.
        guard !isRestoring, isUserScrolling else { return }
        record(next)
    }

    /// View teardown is not a scroll to the bottom. Keep the last valid passage through absent rows.
    public mutating func detach() {
        layout = nil
        isUserScrolling = false
        isRestoring = true
    }

    /// A new gesture takes precedence over restoring an old passage.
    public mutating func userDidScroll() {
        awaitingMissingRow = false
        isUserScrolling = true
        isRestoring = false
    }

    /// Idle layout adjustments are not user intent. Duo can replay an old offset before resizing.
    public mutating func userDidEndScrolling() {
        isUserScrolling = false
    }

    /// A bounded restoration must release capture even when the scroll view clamps the target.
    public mutating func finishRestoration() {
        isUserScrolling = false
        isRestoring = false
        awaitingMissingRow = place.map { layout?.rows[$0.id] == nil } ?? false
        if !awaitingMissingRow, let layout { record(layout) }
    }

    public var isInPlace: Bool {
        guard let layout else { return false }
        guard let place else { return layout.isAtLatest }
        guard let row = layout.rows[place.id] else { return false }
        let wanted = place.anchorY * (layout.viewport.height - row.height)
        return abs(row.minY - layout.viewport.minY - wanted) < 0.5
    }

    private mutating func record(_ layout: Layout) {
        guard !layout.rows.isEmpty else { return }
        if layout.isAtLatest {
            place = nil
            return
        }
        let visible = layout.rows.filter {
            $0.value.height > 0 && $0.value.intersects(layout.viewport)
                && abs(layout.viewport.height - $0.value.height) > 0.5
        }.sorted {
            $0.value.minY == $1.value.minY ? $0.key < $1.key : $0.value.minY < $1.value.minY
        }
        // Keep an already aligned anchor through rounding and late lazy-stack measurements.
        if place != nil, isInPlace { return }
        let row =
            visible.first {
                $0.value.minY >= layout.viewport.minY && $0.value.maxY <= layout.viewport.maxY
            } ?? visible.first
        guard let row else { return }
        // scrollTo aligns the same fractional point of the row and viewport. An ID alone loses
        // this offset; a raw content offset loses the passage when earlier rows wrap differently.
        let anchor = (row.value.minY - layout.viewport.minY) / (layout.viewport.height - row.value.height)
        guard anchor.isFinite else { return }
        place = Place(id: row.key, anchorY: anchor)
    }
}
