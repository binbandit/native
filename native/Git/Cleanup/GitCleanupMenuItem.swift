import SwiftUI

/// "Clean Up Merged…" in a project's menu: opens the review of its merged branches and worktrees.
struct GitCleanupMenuItem: View {
    // Optional: windows without the Git feature (previews, the gallery) leave the item out.
    @Environment(GitCleanupCenter.self) private var center: GitCleanupCenter?
    let project: Project

    var body: some View {
        if let center {
            Button("Clean Up Merged…") {
                center.open(project)
            }
        }
    }
}
