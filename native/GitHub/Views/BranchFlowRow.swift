import SwiftUI

/// `head → base`: the branch with the changes, and an editable base that defaults to the
/// repository's default branch.
struct BranchFlowRow<Field: Hashable>: View {
    let head: String
    @Binding var base: String
    let placeholder: String
    var focus: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        HStack(spacing: DS.Space.md) {
            BranchChip(name: head)
            Image(systemName: "arrow.right")
                .font(.system(size: DS.Size.navIcon - DS.Space.xxs, weight: .medium))
                .foregroundStyle(.dsTextTertiary)
                .accessibilityLabel("into")
            TextField("Base branch", text: $base, prompt: Text(placeholder).foregroundStyle(.dsTextTertiary))
                .textFieldStyle(.plain)
                .font(.dsMonoCaption)
                .focused(focus, equals: field)
                .frame(width: DS.Size.sidebarWidth / 2 + DS.Space.xl)
                .formFieldChrome(isFocused: focus.wrappedValue == field, height: DS.Size.controlXS)
                .help("The branch to merge into")
            Spacer(minLength: 0)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Branch flow row") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            BranchFlowRowPreview(base: "main")
            BranchFlowRowPreview(base: "")
        }
        .frame(width: 520)
    }
}

/// Holds the base branch and focus the row takes as bindings.
private struct BranchFlowRowPreview: View {
    @State var base: String
    @FocusState private var focus: Int?

    var body: some View {
        BranchFlowRow(
            head: "native/queue-follow-ups", base: $base, placeholder: "main", focus: $focus, field: 0)
    }
}
#endif
