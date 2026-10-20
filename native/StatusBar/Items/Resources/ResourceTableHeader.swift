import SwiftUI

/// The table's column titles (Name, CPU, Memory). Each one sorts by its column; the current
/// sort is in the primary color.
struct ResourceTableHeader: View {
    @Binding var sort: ResourceSort

    var body: some View {
        HStack(spacing: 0) {
            column(.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            column(.cpu)
                .frame(width: StatusBarMetrics.cpuColumn, alignment: .trailing)
            column(.memory)
                .frame(width: StatusBarMetrics.memoryColumn, alignment: .trailing)
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlXS)
    }

    private func column(_ column: ResourceSort) -> some View {
        Button(column.title) {
            sort = column
        }
        .buttonStyle(.plain)
        .font(.dsCaption)
        .foregroundStyle(sort == column ? .dsTextPrimary : .dsTextTertiary)
        .help(column == .name ? "Sort as found" : "Sort by \(column.title)")
        .accessibilityLabel("Sort by \(column.title)")
        .accessibilityAddTraits(sort == column ? .isSelected : [])
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Resource table header") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ResourceTableHeader(sort: .constant(.memory))
            ResourceTableHeader(sort: .constant(.cpu))
        }
        .frame(width: 420)
    }
}
#endif
