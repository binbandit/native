import CoreGraphics
import Foundation

/// The widths the breakdown's bar draws its segments at. Slivers too thin to see merge into a
/// neighbor of the same group, every group in use stays visible, and the free space gives up what
/// that costs.
struct ContextBarLayout {
    struct Piece: Hashable, Identifiable {
        let kind: ContextComposition.Segment.Kind
        /// The categories drawn as this piece, more than one when slivers merged.
        let names: [String]
        let tokens: Int
        var width: CGFloat

        var id: String { names.joined(separator: "+") }
    }

    let pieces: [Piece]

    init(_ composition: ContextComposition, width: CGFloat, gap: CGFloat, minWidth: CGFloat, mergeBelow: CGFloat) {
        let segments = composition.segments.filter { $0.tokens > 0 }
        let total = CGFloat(composition.drawnTokens)
        let available = max(width - gap * CGFloat(max(segments.count - 1, 0)), 0)
        let natural = { (tokens: Int) in CGFloat(tokens) / total * available }

        var merged: [Piece] = []
        for segment in segments {
            if let last = merged.last, last.kind == segment.kind, natural(segment.tokens) < mergeBelow || natural(last.tokens) < mergeBelow {
                merged[merged.count - 1] = Piece(kind: last.kind, names: last.names + [segment.name], tokens: last.tokens + segment.tokens, width: 0)
            } else {
                merged.append(Piece(kind: segment.kind, names: [segment.name], tokens: segment.tokens, width: 0))
            }
        }

        // Merging freed some gaps; the pieces share that space too.
        let space = max(width - gap * CGFloat(max(merged.count - 1, 0)), 0)
        var pieces = merged.map { piece in
            var piece = piece
            piece.width = max(CGFloat(piece.tokens) / total * space, minWidth)
            return piece
        }
        let excess = pieces.reduce(0) { $0 + $1.width } - space
        if excess > 0, let widest = pieces.indices.max(by: { pieces[$0].width < pieces[$1].width }) {
            pieces[widest].width = max(pieces[widest].width - excess, minWidth)
        }
        self.pieces = pieces
    }
}
