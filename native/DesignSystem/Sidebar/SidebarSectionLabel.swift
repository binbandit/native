import SwiftUI

/// All in view's one header style: Pinned, archived projects and anything else that names a group
/// of rows reads exactly like a project header, on the task titles' left edge.
public struct SidebarSectionLabel<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    public init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: DS.Space.xxs) {
            Text(title)
                .font(DS.Sidebar.projectFont)
                .tracking(DS.Sidebar.headerTracking)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            accessory
        }
        .padding(.leading, DS.Sidebar.headerLeading)
        .padding(.trailing, DS.Sidebar.trailing)
        .frame(minHeight: DS.Sidebar.headerHeight)
    }
}

extension SidebarSectionLabel where Accessory == EmptyView {
    public init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// A quiet row that folds rows away: "2 earlier" and "Archived". Its chevron follows the words, and
/// a count, when there is one, sits at the trailing edge.
public struct SidebarFoldRow: View {
    let title: String
    var count: Int?
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ title: String, count: Int? = nil, isExpanded: Binding<Bool>) {
        self.title = title
        self.count = count
        _isExpanded = isExpanded
    }

    public var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .dsDisclosure) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Text(title).font(DS.Sidebar.foldFont)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(DS.Sidebar.foldChevronFont)
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)").font(DS.Sidebar.countFont)
                }
            }
            .foregroundStyle(.dsTextTertiary)
            .padding(.leading, DS.Sidebar.headerLeading)
            .padding(.trailing, DS.Sidebar.trailing)
            .frame(minHeight: max(DS.Sidebar.foldHeight, DS.Size.minimumHitTarget))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

#if DEBUG
#Preview("Section label and fold rows") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionLabel("Pinned")
            SidebarSectionLabel("a-project-with-a-long-folder-name-that-truncates") {
                IconButton("Unarchive", systemImage: "arrow.uturn.backward", size: .small) {}
            }
            SidebarFoldRow("2 earlier", isExpanded: .constant(false))
            SidebarFoldRow("Archived", count: 12, isExpanded: .constant(true))
        }
        .frame(width: DS.Size.sidebarWidth - DS.Sidebar.inset * 2)
    }
}
#endif
