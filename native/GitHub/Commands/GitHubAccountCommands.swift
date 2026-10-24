import NativeCommands
import SwiftUI

extension CommandID {
    static let gitHubAccounts: Self = "github.accounts"
}

extension NativeCommand {
    static func gitHubAccounts(settings: SettingsPresentation) -> NativeCommand {
        NativeCommand(
            .gitHubAccounts, title: "GitHub Account…", category: .navigation,
            systemImage: "person.crop.circle", keywords: ["github", "account", "switch", "sign in"]
        ) { _ in
            settings.open(.general, revealing: GitHubAccountsSettingsSection.accountsRow)
        }
    }
}
