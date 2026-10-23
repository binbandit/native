import AppAppearance
import SwiftUI

/// Only collisions that priority can settle appear here.
struct CelebrationOverlaps: View {
    let overlaps: [CelebrationOverlap]
    @Environment(CelebrationCenter.self) private var center

    var body: some View {
        if !overlaps.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                SettingsSubheading("When two land on the same day")
                SettingsRowGroup {
                    ForEach(overlaps) { overlap in
                        let first = name(overlap.first)
                        let second = name(overlap.second)
                        SettingsRow(
                            "\(first) and \(second)",
                            description: Text(
                                "\(CelebrationDates.shortText(overlap.days)), \(overlap.tier == .core ? "both on their own dates" : "both in their longer seasons")"
                            )
                        ) {
                            SettingsSelect(
                                label: "Which shows first on \(CelebrationDates.accessible(overlap.days))",
                                selection: Binding(
                                    get: { preferred(overlap) },
                                    set: {
                                        center.prefer($0, over: $0 == overlap.first ? overlap.second : overlap.first)
                                    }),
                                options: [
                                    .init(value: overlap.first, title: "\(first) first"),
                                    .init(value: overlap.second, title: "\(second) first"),
                                ])
                        }
                    }
                }
                Text(
                    "A celebration on its own dates always wins over another's longer season, so only these need a choice."
                )
                .settingsText(.caption).foregroundStyle(.dsTextSecondary)
            }
        }
    }

    private func name(_ id: CelebrationID) -> String {
        center.catalog.celebration(id)?.contribution.title.resolved() ?? id.rawValue
    }

    private func preferred(_ overlap: CelebrationOverlap) -> CelebrationID {
        center.preferences.order(in: center.celebrations).first { $0 == overlap.first || $0 == overlap.second }
            ?? overlap.first
    }
}

#if DEBUG
#Preview("Celebrations - Collisions") {
    DSPreviewPair { CelebrationPreviewGallery(.overlaps).settingsPreviewPage() }.environment(SettingsPresentation())
}
#endif
