import SwiftUI

/// Information with nothing to change: what something is, what it does, what Native sends. It sits
/// in its own outlined card, 16pt in, with a medium title over muted text, apart from the rows, so it
/// never reads as a setting. Something that has gone wrong or needs the user is a `NoticeBanner`
/// instead.
///
///     SettingsNote("Where worktrees live") { Text("In ~/.native/worktrees, one folder per task.") }
struct SettingsNote<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        Card(padding: DS.Space.xl) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.lg) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: SettingsMetrics.navGlyph))
                        .foregroundStyle(.dsTextSecondary)
                        .frame(width: SettingsMetrics.navIcon)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if let title {
                        Text(title)
                            .settingsText(.bodyMedium)
                            .foregroundStyle(.dsTextPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    content
                        .font(SettingsTextStyle.body.font)
                        .lineSpacing(SettingsTextStyle.body.leading)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Settings note") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            SettingsRowGroup {
                SettingsRow("Rename branches from the task", description: Text("Until it's pushed.")) {
                    SettingsSwitch("Rename branches from the task", isOn: .constant(true))
                }
            }
            SettingsNote("Where worktrees live", systemImage: "folder") {
                Text("In ~/.native/worktrees, one folder per task. Archiving a task removes its folder.")
            }
        }
        .frame(width: 560)
        .padding(DS.Space.xl)
    }
}
