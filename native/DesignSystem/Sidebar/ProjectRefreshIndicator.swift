import SwiftUI

/// Repository work stays neutral; amber belongs to tasks that need the user.
struct ProjectRefreshIndicator: View {
    var body: some View {
        DotGridLoader(pattern: .settingUp)
            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
            .foregroundStyle(.dsTextTertiary)
            .help("Refreshing task state")
            .accessibilityLabel("Refreshing task state")
    }
}

#if DEBUG
#Preview("Project refresh") {
    DSPreviewPair { ProjectRefreshIndicator() }
}
#endif
