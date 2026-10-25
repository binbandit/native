import SwiftUI

struct SidebarEarlierDisclosure: View {
    let count: Int
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .dsDisclosure) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Text("\(count) earlier").font(DS.Sidebar.foldFont)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(DS.Sidebar.foldChevronFont)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.dsTextTertiary)
            .padding(.leading, DS.Sidebar.headerLeading)
            .padding(.trailing, DS.Sidebar.trailing)
            .frame(minHeight: max(DS.Sidebar.foldHeight, DS.Size.minimumHitTarget))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityLabel("\(count) earlier tasks")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
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
