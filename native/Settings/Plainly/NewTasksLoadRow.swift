import SwiftUI

/// One thing a new task loads. Every row has the same shape and height: the name, one line of
/// where it comes from (or what's wrong with it), then an optional action, the token count in a
/// shared column, and a fixed slot holding a switch, a lock or nothing.
struct NewTasksLoadRow: View {
    let item: NewTasksLoadItem
    /// The glyph of the item's source, as source tags draw it.
    var sourceSymbol: String?
    var onInspect: () -> Void
    var onSwitch: (Bool) -> Void
    var onReview: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(item.name)
                    .font(.dsMonoCaption)
                    .foregroundStyle(item.included ? .dsTextPrimary : .dsTextTertiary)
                    .lineLimit(1)
                origin
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: DS.Space.md) {
                if item.needsAttention {
                    Button("Review…", action: onReview).buttonStyle(.settings).fixedSize()
                }
                Button(action: onInspect) {
                    Text(item.tokens.map { DSFormat.tokens($0) } ?? "-")
                        .font(.dsMonoCaption).foregroundStyle(.dsTextTertiary)
                        .strikethrough(!item.included)
                        .frame(width: DS.Settings.loadTokenColumn, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(item.name), \(item.tokens.map { "about \(DSFormat.tokens($0)) tokens" } ?? "not counted")")
                control.frame(width: DS.Settings.loadControlSlot, alignment: .trailing)
            }
            .fixedSize()
        }
        .frame(minHeight: DS.Settings.controlHeight)
    }

    /// Where it comes from, or the one thing to know about it, on a single line.
    private var origin: some View {
        HStack(spacing: DS.Space.xs) {
            if item.detail == nil, let sourceSymbol { Image(systemName: sourceSymbol) }
            Text(item.detail ?? item.loadedBy.map { "\(item.source) · loaded by \($0)" } ?? item.source)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(DS.Settings.caption)
        .foregroundStyle(.dsTextTertiary)
        .help(item.detail ?? "")
    }

    @ViewBuilder private var control: some View {
        switch item.control {
        case .switchable(let enabled):
            SettingsSwitch(item.name, isOn: Binding(get: { enabled }, set: { onSwitch($0) }))
        case .required:
            Button(action: onInspect) {
                Image(systemName: "lock").foregroundStyle(.dsTextTertiary)
            }
            .buttonStyle(.plain).accessibilityLabel("\(item.name), required by \(item.source)")
        case .unavailable(let reason):
            Button(action: onInspect) {
                Image(systemName: "lock").foregroundStyle(.dsTextTertiary)
            }
            .buttonStyle(.plain).help(reason).accessibilityLabel(reason)
        case .agentOwned:
            // The agent decides; its source already says so.
            Color.clear.frame(height: 0)
        }
    }
}

#if DEBUG
#Preview("New Tasks - Load rows: on, off, required, failed") {
    DSPreviewPair {
        SettingsRowGroup {
            ForEach(NewTasksPreviewFixtures.items(project: "pier", organization: "Northwind Federal IT")) { item in
                NewTasksLoadRow(item: item, onInspect: {}, onSwitch: { _ in }, onReview: {})
            }
        }.settingsPreviewPage()
    }.environment(\.settingsPlainly, true)
}
#endif
