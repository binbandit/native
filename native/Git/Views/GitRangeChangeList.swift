import Git
import SwiftUI

/// The files a turn or a branch changed. A turn's card lists its files first, then anything else
/// that changed meanwhile, each under a header once there are both; undone changes are noted below.
struct GitRangeChangeList: View {
    let model: GitRangeModel
    let comparison: GitRangeComparison
    /// The repository's root on this machine, for opening files.
    let root: URL?

    var body: some View {
        let selection = model.selection
        let sections = Self.sections(of: comparison)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.changes) { change in
                            GitRangeChangeRow(
                                change: change, isSelected: selection == change.path, root: root,
                                onSelect: { model.selection = change.path })
                        }
                    } header: {
                        if sections.count > 1 {
                            GitRangeSectionHeader(
                                title: section.title, count: section.changes.count,
                                isFirst: section.title == sections.first?.title)
                        }
                    }
                }
                if let footnote = Self.undoneFootnote(comparison) {
                    Text(footnote)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.sm)
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.top, sections.count > 1 ? 0 : DS.Space.sm)
            .padding(.bottom, DS.Space.md)
        }
    }

    /// The list's height with nothing scrolled away, so the diff below can have the rest.
    static func contentHeight(for comparison: GitRangeComparison) -> CGFloat {
        let sections = sections(of: comparison)
        let headers = sections.count > 1 ? CGFloat(sections.count) * GitRangeSectionHeader.height : DS.Space.sm
        let rows = CGFloat(comparison.changes.count + (undoneFootnote(comparison) == nil ? 0 : 1))
        return headers + rows * GitMetrics.rowHeight + DS.Space.md
    }

    private static func sections(of comparison: GitRangeComparison) -> [(title: String, changes: [TreeChange])] {
        guard comparison.isTurn else { return [("Changes", comparison.changes)] }
        let others = comparison.startsAtTurn ? "Also changed since it began" : "Other changes on this branch"
        return [("Edited in this turn", comparison.edited), (others, comparison.others)].filter { !$0.changes.isEmpty }
    }

    /// "README.md is back to how it was when the turn began."
    static func undoneFootnote(_ comparison: GitRangeComparison) -> String? {
        let undone = comparison.undone
        guard comparison.startsAtTurn, let first = undone.first else { return nil }
        if undone.count == 1 {
            return "\(URL(filePath: first).lastPathComponent) is back to how it was when the turn began."
        }
        return "\(undone.count) files are back to how they were when the turn began."
    }
}

/// A group's title and count in the list, styled like the uncommitted list's area headers.
private struct GitRangeSectionHeader: View {
    let title: String
    let count: Int
    let isFirst: Bool

    /// Its height in the list, the gap above it included.
    static let height = DS.Size.controlXS + DS.Space.sm + DS.Space.xxs

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(title)
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
            Text("\(count)")
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextQuaternary)
            Spacer(minLength: DS.Space.md)
        }
        .tracking(DS.Tracking.tight)
        .padding(.leading, DS.Space.md)
        .frame(height: DS.Size.controlXS)
        .padding(.top, isFirst ? DS.Space.sm : DS.Space.sm + DS.Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Turn changes - File list") {
    let comparison = GitPreviewFixtures.turnComparison(.turnSnapshot)
    return DSPreviewPair {
        GitRangeChangeList(model: GitRangeModel(fixed: comparison), comparison: comparison, root: nil)
            .frame(width: GitMetrics.inspectorIdealWidth, height: 240)
    }
}
#endif
