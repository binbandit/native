import Foundation

/// Where clicking a pull request takes the user: its page in Native, or GitHub in the browser.
enum GitHubPullRequestOpening: String, CaseIterable, Identifiable, Sendable {
    case native
    case browser

    var id: Self { self }

    var title: String {
        switch self {
        case .native: "In Native"
        case .browser: "In browser"
        }
    }

    static let defaultsKey = "gitHub.openPullRequestsIn"

    static var stored: Self {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .native
    }
}
