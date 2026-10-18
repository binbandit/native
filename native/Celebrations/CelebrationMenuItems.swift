import AppAppearance
import NativeCommands
import SwiftUI

extension CommandID {
    static let celebrationRestore: Self = "celebration.restore"
    static let celebrationChoose: Self = "celebration.choose"
}

extension NativeCommand {
    /// Put the usual look back (or bring a skipped celebration back) with ⌥⇧⌘H, and open the chooser.
    static func celebrations(_ center: CelebrationCenter, settings: SettingsPresentation) -> [NativeCommand] {
        func skipped() -> String? {
            guard let skipped = center.resolution.skipped.first, center.resolution.active == nil,
                let event = center.catalog.celebration(skipped.eventID)
            else { return nil }
            return event.contribution.title.resolved()
        }
        return [
            NativeCommand(
                .celebrationRestore, title: "Restore Usual Appearance", category: .view, systemImage: "sparkles",
                keywords: ["celebration", "icon", "halloween", "holiday"]
            ) { _ in
                if skipped() != nil {
                    center.resumeToday()
                } else {
                    center.restoreBase()
                }
            }
            .menuTitle { _ in skipped().map { "Bring Back \($0)" } ?? "Restore Usual Appearance" }
            .available { _ in skipped() != nil || center.resolution.active != nil },

            NativeCommand(
                .celebrationChoose, title: "Celebrations…", category: .view, systemImage: "party.popper",
                keywords: ["holiday", "theme"]
            ) { context in
                context.openMainWindow()
                settings.open(.celebrations)
            },
        ]
    }
}
