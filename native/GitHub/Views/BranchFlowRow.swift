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
