import SwiftUI

struct SidebarEarlierDisclosure: View {
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        SidebarFoldRow("\(count) earlier", isExpanded: $isExpanded)
            .accessibilityLabel("\(count) earlier tasks")
            .help(isExpanded ? "Hide earlier tasks" : "Show earlier tasks")
    }
}

#if DEBUG
#Preview("Earlier tasks - Folded and expanded") {
    DSPreviewPair {
        VStack(spacing: 0) {
            SidebarEarlierDisclosure(count: 2, isExpanded: .constant(false))
            SidebarEarlierDisclosure(count: 12, isExpanded: .constant(true))
        }.frame(width: DS.Size.sidebarWidth)
    }
}
#endif
