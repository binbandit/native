import SwiftUI

/// A New Tasks value with its source beside it. The tag appears only when someone other than the
/// user set the value. In a narrow group every tag shrinks to its glyph together
/// (`newTasksCompactSources`), and the source stack still names it. The stack opens from the tag,
/// or from the row's "Why This Value…".
struct NewTasksSourceControl<Content: View>: View {
    let receipt: NewTasksSettingReceipt
    @Binding var showsSource: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.newTasksCompactSources) private var compact

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if !receipt.source.isQuiet {
                Button {
                    showsSource = true
                } label: {
                    SettingsSourceLabel(source: receipt.source, compact: compact)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .layoutPriority(1)
                .dsHitTarget(DS.Settings.controlHeight)
                .accessibilityLabel("\(receipt.title) source: \(receipt.source.title)")
            }
            content()
        }
        .popover(isPresented: $showsSource) { NewTasksSourceStack(receipt: receipt) }
    }
}

extension EnvironmentValues {
    /// Source tags show only their glyph, for a group too narrow for the names.
    @Entry var newTasksCompactSources = false
}

#if DEBUG
#Preview("New Tasks - Source control, full and narrow") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.lg) {
            NewTasksSourceControl(
                receipt: NewTasksPreviewFixtures.receipt(managed: true), showsSource: .constant(false)
            ) {
                SettingsValue("Edit files")
            }
            NewTasksSourceControl(
                receipt: NewTasksPreviewFixtures.receipt(managed: true), showsSource: .constant(false)
            ) {
                SettingsValue("Edit files")
            }
            .environment(\.newTasksCompactSources, true)
        }.padding(DS.Space.lg)
    }
}
#endif
