import SwiftUI

/// A list section's title with trailing actions, like the sidebar's "Projects" row: 12pt tertiary
/// label, small icon buttons for filter and add.
public struct SectionHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    public init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: DS.Space.xxs) {
            Text(title)
                .font(.dsBody)
                .tracking(DS.Tracking.tight)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.md)
            accessory
        }
        .padding(.leading, DS.Space.sm)
        .frame(minHeight: DS.Size.controlXS)
    }
}

extension SectionHeader where Accessory == EmptyView {
    public init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

#Preview("Section header") {
    DSPreviewPair {
        SectionHeader("Projects") {
            IconButton("Filter", systemImage: "line.3.horizontal.decrease") {}
            IconButton("Add Project", systemImage: "folder.badge.plus") {}
        }
        .frame(width: 232)
    }
}
