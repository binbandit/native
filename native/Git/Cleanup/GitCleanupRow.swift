import SwiftUI

/// One thing Clean Up Merged would remove: a checkbox while choosing (its state glyph once the work
/// starts), what it is, why it qualifies, where it is, what to watch out for, and its size. A
/// failure shows under it, in its own words.
struct GitCleanupRow: View {
    let model: GitCleanupModel
    let item: GitCleanupItem

    var body: some View {
        let isEnabled = model.isEnabled(item)
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            leading
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + GitCleanupMetrics.glyphBaseline }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(item.title)
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                reason
                if let detail = item.detail {
                    Text(detail)
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let warning = item.warning, model.phase == .review {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.dsCaption)
                        .foregroundStyle(.dsWarning)
                        .help(warningHelp)
                }
                if case .failed(let message)? = model.states[item.id] {
                    Text(message)
                        .font(.dsCaption)
                        .foregroundStyle(.dsDanger)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let bytes = item.bytes {
                Text(DSFormat.fileSize(bytes))
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        .padding(.vertical, DS.Space.sm)
        .opacity(model.phase == .review && !isEnabled ? GitCleanupMetrics.disabledOpacity : 1)
        .contentShape(.rect)
        .onTapGesture { model.toggle(item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.title, item.reason, item.warning].compactMap(\.self).joined(separator: ", "))
        .accessibilityAddTraits(model.phase == .review ? .isToggle : [])
        .accessibilityValue(accessibilityValue)
        .accessibilityAction { model.toggle(item) }
        .help(item.location ?? "")
    }

    @ViewBuilder private var leading: some View {
        switch model.phase {
        case .review:
            GitCheckbox(value: model.isIncluded(item) ? .on : .off, label: "Include \(item.title)") {
                model.toggle(item)
            }
            .disabled(!model.isEnabled(item))
            .help(model.isEnabled(item) ? "" : "Included with its worktree")
        default:
            stateGlyph
                .frame(width: GitMetrics.checkbox, height: GitMetrics.checkbox)
        }
    }

    @ViewBuilder private var stateGlyph: some View {
        switch model.states[item.id] {
        case .working?:
            DotGridLoader(pattern: .typing)
                .foregroundStyle(.dsTextSecondary)
        case .done?:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.dsSuccess)
        case .failed?:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.dsDanger)
        case nil:
            Image(systemName: "circle")
                .foregroundStyle(.dsTextQuaternary)
        }
    }

    @ViewBuilder private var reason: some View {
        if let link = item.pullRequest {
            Link(destination: link) {
                Text(item.reason)
                    .font(.dsBody)
                    .foregroundStyle(.dsAccentText)
            }
            .help(link.absoluteString)
        } else {
            Text(item.reason)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        }
    }

    private var warningHelp: String {
        switch item.id {
        case .worktree:
            "Removing it saves uncommitted work as a checkpoint, and Unarchive brings it back. Included only if you check it."
        default: ""
        }
    }

    private var accessibilityValue: String {
        switch model.states[item.id] {
        case .working?: "Cleaning up"
        case .done?: "Done"
        case .failed(let message)?: "Failed: \(message)"
        case nil: model.isIncluded(item) ? "Included" : "Not included"
        }
    }
}

#if DEBUG
#Preview("Cleanup rows") {
    let app = AppModel.preview()
    let model = GitCleanupModel(
        project: app.previewProject() ?? Project(url: URL(filePath: "/")),
        services: GitPreviewFixtures.cleanupServices(app))
    model.phase = .review
    let running = GitCleanupModel(
        project: app.previewProject() ?? Project(url: URL(filePath: "/")),
        services: GitPreviewFixtures.cleanupServices(app))
    running.phase = .running
    let items = GitPreviewFixtures.cleanupItems
    running.states = [
        items[0].id: .done, items[1].id: .working, items[2].id: .failed("branch is checked out in another worktree"),
    ]
    return DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(items) { item in
                GitCleanupRow(model: model, item: item)
            }
            SeparatorLine()
            ForEach(items.prefix(3)) { item in
                GitCleanupRow(model: running, item: item)
            }
        }
        .frame(width: GitCleanupMetrics.sheetWidth - DS.Space.xxl)
    }
}
#endif
