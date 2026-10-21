import SwiftUI

/// The inspector's choice of changes: this turn's, the uncommitted ones, or the branch's.
struct GitChangesScopePicker: View {
    @Binding var scope: GitChangesScope

    var body: some View {
        Picker("Changes to show", selection: $scope) {
            ForEach(GitChangesScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, DS.Space.md)
        .frame(maxWidth: .infinity)
        .frame(height: GitMetrics.scopeBarHeight)
    }
}

#if DEBUG
#Preview("Scope picker") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            GitChangesScopePicker(scope: .constant(.turn))
            GitChangesScopePicker(scope: .constant(.branch))
        }
        .frame(width: GitMetrics.inspectorIdealWidth)
    }
}
#endif
