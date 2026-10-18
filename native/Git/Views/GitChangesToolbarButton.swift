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
            // A plain stack rather than a `Label`: in a toolbar, a Label's title becomes the item's
            // name, which would read "+4" instead of the button's own label.
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "plus.forwardslash.minus")
                if totals.additions > 0 || totals.deletions > 0 {
                    DiffStatLabel(added: totals.additions, removed: totals.deletions)
                }
            }
        }
        .buttonStyle(.header(isOn: isPresented, iconOnly: totals.additions == 0 && totals.deletions == 0))
        .help(CommandRegistry.shared.help(isPresented ? "Hide Changes" : "Show Changes", for: .viewToggleChanges))
        .accessibilityLabel(isPresented ? "Hide Changes" : "Show Changes")
        .accessibilityAddTraits(isPresented ? .isSelected : [])
        .accessibilityValue("\(totals.additions) lines added, \(totals.deletions) removed")
        .disabled(model.state == .notRepository)
    }
}
