import SwiftUI

/// What a project's tasks are doing, for its header while it's collapsed: how many need the user
/// and how many are working.
public struct ProjectActivity: Equatable, Sendable {
    public var needsYou: Int
    public var working: Int

    public init(needsYou: Int = 0, working: Int = 0) {
        self.needsYou = needsYou
        self.working = working
    }

    public var isEmpty: Bool {
        needsYou == 0 && working == 0
    }

    /// "1 needs you, 2 working", for VoiceOver and the tooltip.
    public var label: String? {
        let parts = [
            needsYou > 0 ? "\(needsYou) \(needsYou == 1 ? "needs" : "need") you" : nil,
            working > 0 ? "\(working) working" : nil,
        ]
        .compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// A collapsed project's activity, compact: the needs-you marker and its count, then the working
/// loader and its count, in the task status glyphs (`StatusIndicator`), so a working loader is the
/// same Core Animation one the rows use and costs nothing per frame.
struct ProjectActivityLabel: View {
    let activity: ProjectActivity

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if activity.needsYou > 0 {
                item(.needsPermission, count: activity.needsYou, tint: .dsAttention)
            }
            if activity.working > 0 {
                item(.working, count: activity.working, tint: .dsTextTertiary)
            }
        }
        .help(activity.label ?? "")
        .accessibilityHidden(true)
    }

    private func item(_ status: TaskStatus, count: Int, tint: Color) -> some View {
        HStack(spacing: DS.Space.xxs) {
            StatusIndicator(status: status, size: 12)
            Text("\(count)")
                .font(.dsMonoCaption)
                .foregroundStyle(tint)
        }
    }
}

#Preview("Project activity") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ProjectActivityLabel(activity: ProjectActivity(needsYou: 1, working: 2))
            ProjectActivityLabel(activity: ProjectActivity(working: 3))
            ProjectActivityLabel(activity: ProjectActivity(needsYou: 2))
        }
    }
}
