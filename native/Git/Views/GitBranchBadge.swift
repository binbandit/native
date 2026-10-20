import Git
import SwiftUI

/// A branch at a glance: name, a dot when the working tree has changes, and commits ahead of and
/// behind its upstream. For sidebar task rows, window subtitles and the inspector header.
struct GitBranchBadge: View {
    enum Style {
        /// Icon, name, dirty dot and arrows.
        case regular
        /// Only the dirty dot and arrows, for a one-line task row; the name is in the tooltip.
        case compact
    }

    let branch: BranchStatus
    var isDirty = false
    var font: Font = .dsCaption
    var style = Style.regular

    var body: some View {
        if style == .compact {
            badge.help(accessibilityText)
        } else {
            badge
        }
    }

    private var badge: some View {
        HStack(spacing: DS.Space.xs) {
            if style == .regular {
                Image(systemName: branch.isDetached ? "smallcircle.filled.circle" : "arrow.triangle.branch")
                    .imageScale(.small)
                    .foregroundStyle(.dsTextTertiary)
                Text(branch.displayName)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if isDirty {
                StatusDot(color: .dsWarning)
                    .help("Uncommitted changes")
            }
            if branch.ahead > 0 {
                Text("↑\(branch.ahead)")
                    .help("\(branch.ahead) commits to push")
            }
            if branch.behind > 0 {
                Text("↓\(branch.behind)")
                    .help("\(branch.behind) commits to pull")
            }
            if branch.isUpstreamGone {
                Image(systemName: "icloud.slash")
                    .imageScale(.small)
                    .help("The upstream branch was deleted")
            }
        }
        .font(font)
        .monospacedDigit()
        .tracking(DS.Tracking.tight)
        .foregroundStyle(.dsTextTertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [branch.isDetached ? "Detached at \(branch.displayName)" : "Branch \(branch.displayName)"]
        if isDirty { parts.append("uncommitted changes") }
        if branch.ahead > 0 { parts.append("\(branch.ahead) ahead") }
        if branch.behind > 0 { parts.append("\(branch.behind) behind") }
        return parts.joined(separator: ", ")
    }
}

extension GitBranchBadge {
    /// The badge for a folder's live model; empty outside a repository.
    struct Live: View {
        let model: GitRepositoryModel
        var font: Font = .dsCaption
        var style = Style.regular

        var body: some View {
            if let branch = model.branch {
                GitBranchBadge(branch: branch, isDirty: model.isDirty, font: font, style: style)
            }
        }
    }
}

#if DEBUG
#Preview("Branch badge") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            GitBranchBadge(branch: GitPreviewFixtures.branch, isDirty: true)
            GitBranchBadge(branch: BranchStatus(head: .branch("main"), commit: "abc", upstream: "origin/main"))
            GitBranchBadge(branch: BranchStatus(head: .detached, commit: "9e8d7c6b5a"), isDirty: true)
            GitBranchBadge(
                branch: BranchStatus(
                    head: .branch("native/diff-view-word-wrapping-in-narrow-windows-without-breaking-the-gutter"),
                    commit: "1a2b3c4"))
        }
        .frame(width: 280, alignment: .leading)
    }
}
#endif
