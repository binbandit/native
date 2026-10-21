import SwiftUI

/// What sits beside a fact's text: its diff stat, a loader while it runs, a red dot after a
/// failure, or an app's icon.
struct SessionToolFactAccessory: View {
    let accessory: SessionToolFact.Accessory?

    var body: some View {
        switch accessory {
        case .diff(let added, let removed):
            DiffStatLabel(added: added, removed: removed)
        case .working:
            DotGridLoader(pattern: .waiting)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
        case .failed:
            StatusDot(color: .dsDanger)
        case .icon(let image):
            image
                .resizable()
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
        case nil:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Fact accessories") {
    DSPreviewPair {
        HStack {
            SessionToolFactAccessory(accessory: .diff(added: 12, removed: 3))
            SessionToolFactAccessory(accessory: .working)
            SessionToolFactAccessory(accessory: .failed)
            SessionToolFactAccessory(accessory: nil)
        }
    }
}
#endif
