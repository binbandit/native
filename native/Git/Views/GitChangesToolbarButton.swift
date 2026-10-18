import Git
import SwiftUI

/// The window header's "+N -M" summary of a task's uncommitted changes, in the outlined header
/// style; it shows and hides the changes inspector (⇧⌘D), and stays selected while it's open.
struct GitChangesToolbarButton: View {
    let model: GitRepositoryModel
    @Binding var isPresented: Bool

    var body: some View {
        let totals = model.totals
        Button {
            isPresented.toggle()
        } label: {
            Label {
                if totals.additions > 0 || totals.deletions > 0 {
                    DiffStatLabel(added: totals.additions, removed: totals.deletions)
                }
            } icon: {
                Image(systemName: "plus.forwardslash.minus")
            }
        }
        .buttonStyle(.header(isOn: isPresented, iconOnly: totals.additions == 0 && totals.deletions == 0))
        .help(CommandRegistry.shared.help(isPresented ? "Hide Changes" : "Show Changes", for: .viewToggleChanges))
        .accessibilityLabel(isPresented ? "Hide Changes" : "Show Changes")
        .accessibilityValue("\(totals.additions) lines added, \(totals.deletions) removed")
        .disabled(model.state == .notRepository)
    }
}
