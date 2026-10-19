import Git
import SwiftUI

/// A group's title and count in the change list, with buttons that discard and stage (or
/// unstage) the whole group.
struct GitChangeSectionHeader: View {
    let area: FileChange.Area
    let changes: [FileChange]
    /// The first group sits closer to the top of the list.
    let isFirst: Bool
    let model: GitRepositoryModel
    @Binding var pendingDiscard: [FileChange]

    /// Its height in the list, the gap above it included.
    static let height = DS.Size.controlXS + DS.Space.sm + DS.Space.xxs

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(area.title)
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
            Text("\(changes.count)")
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextQuaternary)
            Spacer(minLength: DS.Space.md)
            if area != .staged {
                IconButton("Discard All \(area.title)", systemImage: "arrow.uturn.backward") {
                    pendingDiscard = changes
                }
                .dsHitTarget(DS.Size.controlXS)
            }
            IconButton(area == .staged ? "Unstage All" : "Stage All", systemImage: area == .staged ? "minus" : "plus") {
                let changes = changes
                Task { area == .staged ? await model.unstage(changes) : await model.stage(changes) }
            }
            .dsHitTarget(DS.Size.controlXS)
        }
        .tracking(DS.Tracking.tight)
        .padding(.leading, DS.Space.md)
        .frame(height: DS.Size.controlXS)
        .padding(.top, isFirst ? DS.Space.sm : DS.Space.sm + DS.Space.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(area.title), \(changes.count) files")
    }
}
