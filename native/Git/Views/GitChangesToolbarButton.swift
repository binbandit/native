import Git
import SwiftUI

/// The window toolbar's "+N -M" summary of a task's uncommitted changes; it shows and hides the
/// changes inspector (⌘⇧D).
struct GitChangesToolbarButton: View {
    let model: GitRepositoryModel
    @Binding var isPresented: Bool

    var body: some View {
        let totals = model.totals
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "plus.forwardslash.minus")
                if totals.additions > 0 || totals.deletions > 0 {
                    DiffStatLabel(added: totals.additions, removed: totals.deletions)
                }
            }
        }
        .help(isPresented ? "Hide Changes (⇧⌘D)" : "Show Changes (⇧⌘D)")
        .accessibilityLabel("Changes")
        .accessibilityValue("\(totals.additions) lines added, \(totals.deletions) removed")
        .disabled(model.state == .notRepository)
    }
}
