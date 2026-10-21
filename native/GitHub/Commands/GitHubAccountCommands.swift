import NativeCommands
import SwiftUI

extension CommandID {
    static let gitHubAccounts: Self = "github.accounts"
}

extension NativeCommand {
    static func gitHubAccounts(_ model: GitHubModel, settings: SettingsPresentation) -> NativeCommand {
        NativeCommand(
            .gitHubAccounts, title: "GitHub Account…", category: .navigation,
            systemImage: "person.crop.circle", keywords: ["github", "account", "switch", "sign in"]
        ) { context in
            if settings.isShown { settings.open(.gitHub) }
            context.sidebarVisibility?.wrappedValue = .all
            model.accounts.showMenu()
        }
    }
}
