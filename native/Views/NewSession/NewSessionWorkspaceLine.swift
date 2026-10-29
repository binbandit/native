import SwiftUI

/// Where a new task works, in one exact line: its branch and the branch it starts from, linked by
/// Native's interlock mark ("main ⟗ you/k3x9 · its own worktree"), the project's checkout it shares,
/// or the folder that isn't a repository. Branch names are set in mono, like everywhere else they
/// show. Stacks onto two lines when there's no room for one.
struct NewSessionWorkspaceLine: View {
    let workspace: NewSessionContext.Workspace
    let projectName: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.sm) {
                names
                if let place {
                    Text("·").foregroundStyle(.dsTextQuaternary)
                    Text(place)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                names
                if let place {
                    Text(place)
                }
            }
        }
        .font(.dsCallout)
        .foregroundStyle(.dsTextTertiary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder private var names: some View {
        switch workspace {
        case .worktree(let branch, let base):
            HStack(spacing: DS.Space.sm) {
                if let base {
                    code(base, style: .dsTextSecondary)
                    NewSessionLinkMark()
                }
                code(branch, style: .dsTextPrimary)
            }
        case .checkout(let branch):
            code(branch ?? "detached", style: .dsTextPrimary)
        case .folder(let path), .unknown(let path):
            code(path, style: .dsTextSecondary)
                .truncationMode(.head)
        }
    }

    /// What kind of place it is, after the names.
    private var place: String? {
        switch workspace {
        case .worktree: "its own worktree"
        case .checkout: "project folder"
        case .folder: "not a git repository"
        case .unknown: nil
        }
    }

    private func code(_ text: String, style: Color) -> some View {
        Text(text)
            .font(.dsMono)
            .foregroundStyle(style)
            .truncationMode(.middle)
    }

    private var spoken: String {
        switch workspace {
        case .worktree(let branch, let base):
            if let base {
                "Branch \(branch), from \(base), in its own worktree"
            } else {
                "Branch \(branch), in its own worktree"
            }
        case .checkout(let branch): "On \(branch ?? "a detached head"), in the project folder"
        case .folder(let path): "In \(path), not a git repository"
        case .unknown(let path): "In \(path)"
        }
    }
}

/// Native's interlock mark at text size, linking a task's branch to the one it starts from.
struct NewSessionLinkMark: View {
    var body: some View {
        NativeMark()
            .fill(.dsTextTertiary)
            .frame(
                width: NewSessionMetrics.linkMarkHeight * NativeMark.aspectRatio,
                height: NewSessionMetrics.linkMarkHeight
            )
            .accessibilityHidden(true)
    }
}

/// The project's uncommitted changes, when they matter to the new task: left behind in the
/// project's checkout when the task has its own worktree, or there to start with when it shares it.
struct NewSessionChangesNote: View {
    let count: Int
    let workspace: NewSessionContext.Workspace
    let projectName: String

    var body: some View {
        if count > 0, let text {
            Text(text)
                .font(.dsCallout)
                .foregroundStyle(.dsTextTertiary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String? {
        let changes = count == 1 ? "1 uncommitted change" : "\(count) uncommitted changes"
        return switch workspace {
        case .worktree: "\(changes) in \(projectName) \(count == 1 ? "isn't" : "aren't") in this worktree"
        case .checkout: "Starts with \(changes) already in the project folder"
        case .folder, .unknown: nil
        }
    }
}
