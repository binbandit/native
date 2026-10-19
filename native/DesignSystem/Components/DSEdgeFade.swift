import SwiftUI

extension View {
    /// Fades the view out toward `edges` instead of cutting it off there, for a scroll view whose
    /// content runs past those edges: pass the edges that have more content beyond them, and each
    /// fade comes and goes as they change. Apply it inside any border, so the border stays whole.
    ///
    ///     list.dsEdgeFade(isScrolled ? .top : [])
    public func dsEdgeFade(_ edges: Edge.Set, length: CGFloat = DS.Size.edgeFade) -> some View {
        mask { DSEdgeFadeMask(edges: edges, length: length) }
    }
}

/// Opaque in the middle, clear at each faded edge. Meant for one axis at a time; with both, the
/// corners fade along one of them only.
private struct DSEdgeFadeMask: View {
    let edges: Edge.Set
    let length: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            fade(toward: .top)
                .frame(height: edges.contains(.top) ? length : 0)
            HStack(spacing: 0) {
                fade(toward: .leading)
                    .frame(width: edges.contains(.leading) ? length : 0)
                Rectangle()
                fade(toward: .trailing)
                    .frame(width: edges.contains(.trailing) ? length : 0)
            }
            fade(toward: .bottom)
                .frame(height: edges.contains(.bottom) ? length : 0)
        }
        .animation(.dsQuick, value: edges.rawValue)
    }

    private func fade(toward edge: Edge) -> LinearGradient {
        let (start, end): (UnitPoint, UnitPoint) =
            switch edge {
            case .top: (.bottom, .top)
            case .bottom: (.top, .bottom)
            case .leading: (.trailing, .leading)
            case .trailing: (.leading, .trailing)
            }
        return LinearGradient(colors: [.black, .clear], startPoint: start, endPoint: end)
    }
}

#Preview("Edge fade") {
    DSPreviewPair {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ForEach(0..<20, id: \.self) { row in
                    Text(verbatim: "Row \(row)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.md)
        }
        .frame(height: 120)
        .dsEdgeFade([.top, .bottom])
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsSeparator) }
        .font(.dsBody)
    }
}
