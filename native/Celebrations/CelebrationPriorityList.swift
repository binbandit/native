import AppAppearance
import SwiftUI

/// The order overlapping celebrations follow, once more than one is on. Core dates always come
/// first; this order settles the rest. Buttons rather than drag, so it works with keyboard, pointer,
/// touch and VoiceOver alike.
struct CelebrationPriorityList: View {
    @Environment(CelebrationCenter.self) private var center

    var body: some View {
        let events = center.priority
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                "When celebrations overlap",
                note: "A celebration on its own dates always comes first. Otherwise the first in this list shows.")
            SettingsRowGroup {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(spacing: DS.Space.lg) {
                        Text("\(index + 1)")
                            .settingsText(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.Space.xl)
                        CelebrationPreview(event: event, size: CelebrationMetrics.surfacePreview)
                        Text(event.contribution.title.resolved())
                            .settingsText(.bodyMedium)
                            .foregroundStyle(.dsTextPrimary)
                        Spacer(minLength: 0)
                        IconButton("Move Up", systemImage: "chevron.up") { center.move(event.id, by: -1) }
                            .disabled(index == 0)
                        IconButton("Move Down", systemImage: "chevron.down") { center.move(event.id, by: 1) }
                            .disabled(index == events.count - 1)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(event.contribution.title.resolved()), \(index + 1) of \(events.count)")
                }
            }
        }
    }
}
