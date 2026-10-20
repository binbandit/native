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
        .accessibilityValue(Self.accessibilityValue(for: totals))
        .disabled(model.state == .notRepository)
    }

    /// "1 line added, 2 removed", "3 lines removed", "No changed lines".
    static func accessibilityValue(for totals: LineStats) -> String {
        func lines(_ count: Int) -> String { count == 1 ? "1 line" : "\(count) lines" }
        return switch (totals.additions, totals.deletions) {
        case (0, 0): "No changed lines"
        case (let added, 0): "\(lines(added)) added"
        case (0, let removed): "\(lines(removed)) removed"
        case (let added, let removed): "\(lines(added)) added, \(removed) removed"
        }
    }
}

#if DEBUG
#Preview("Changes toolbar button") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            GitChangesToolbarButton(model: GitPreviewFixtures.model, isPresented: .constant(false))
            GitChangesToolbarButton(model: GitPreviewFixtures.model, isPresented: .constant(true))
            GitChangesToolbarButton(model: GitPreviewFixtures.cleanModel, isPresented: .constant(false))
        }
    }
}
#endif
