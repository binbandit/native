import SwiftUI

/// "Clean Up Merged…" in a project's menu: opens the review of its merged branches and worktrees.
struct GitCleanupMenuItem: View {
    @Environment(GitCleanupCenter.self) private var center
    let project: Project

    var body: some View {
        Button("Clean Up Merged…") {
            center.open(project)
        }
    }
}
