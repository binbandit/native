#if DEBUG
import Git
import SwiftUI

/// A fact's state beside its text: a loader while it runs, a red dot after a failure, the diff stat
/// for changes.
struct SessionChromeFactBadge: View {
    let fact: SessionChromeFact

    var body: some View {
        switch fact.tone {
        case .running:
            DotGridLoader(pattern: .waiting)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
        case .failed:
            StatusDot(color: .dsDanger)
        case .quiet:
            EmptyView()
        }
        if let diff = fact.diff, diff.additions + diff.deletions > 0 {
            DiffStatLabel(added: diff.additions, removed: diff.deletions)
        }
    }
}
#endif
