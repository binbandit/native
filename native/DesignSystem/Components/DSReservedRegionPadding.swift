import SwiftUI

extension View {
    /// Custom horizontal controls respect local camera/system occlusions as well as safe areas.
    /// The query measures the whole padded bar so adding clearance cannot feed back into its bounds.
    func dsReservedRegionPadding() -> some View {
        modifier(DSReservedRegionPadding())
    }
}

private struct DSReservedRegionPadding: ViewModifier {
    @State private var insets = EdgeInsets()

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            content
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
                .onGeometryChange(for: EdgeInsets.self) { geometry in
                    let bounds = CGRect(origin: .zero, size: geometry.size)
                    var result = EdgeInsets()
                    for region in geometry.reservedRegions(kind: .occlusion) {
                        let frame = region.frame
                        guard bounds.intersects(frame) else { continue }
                        // The frame already includes the system's recommended margins.
                        let leading = max(0, frame.maxX)
                        let trailing = max(0, bounds.maxX - frame.minX)
                        if leading < trailing {
                            result.leading = max(result.leading, leading)
                        } else {
                            result.trailing = max(result.trailing, trailing)
                        }
                    }
                    return result
                } action: {
                    insets = $0
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if DEBUG
#Preview("Reserved regions - Custom control") {
    DSPreviewPair {
        Button("Send message", systemImage: "arrow.up") {}
            .dsHitTarget(DS.Size.minimumHitTarget)
            .dsReservedRegionPadding()
            .frame(width: 320)
    }
}
#endif
