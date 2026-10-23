import Foundation

/// Copy shared by a row, its accessible control name and its search result.
struct SettingsPlainlyCopy {
    let title: String
    var description: String?
    var preservesDescription = false

    static let followUp = Self(title: "Return while an agent works")
    static let badge = Self(title: "Badge")
    static let workspace = Self(title: "Work in")
    static let renameBranch = Self(
        title: "Name branches from the task's title", description: "Until the branch is pushed.")
    static let envFiles = Self(
        title: "Copy into each worktree",
        description: "Files git ignores that a task still needs, like .env. Separate with commas.")
    static let deleteBranch = Self(
        title: "Delete the branch when a task is archived",
        description: "Its commits stay, so restoring the task brings it back.")
    static let pullRequests = Self(title: "Open pull requests")
    static let longWork = Self(
        title: "When long work finishes", description: "Says what it did, like “Done in 4m · 7 files changed”.")
    static let threshold = Self(title: "After turns longer than")
    static let needsYou = Self(
        title: "When a task needs you", description: "Approvals and questions you can answer from the notification.")
    static let limits = Self(title: "Usage limits", description: "Before and when a limit is reached.")
    static let keepRunning = Self(
        title: "Keep agents running after you quit", description: "Turn this off to stop agents when Native quits.")
    static let backgroundHelper = Self(title: "Background helper", preservesDescription: true)
    static let awake = Self(title: "Keep Mac awake", description: "Closing the lid still sleeps your Mac.")
    static let awakeTimer = Self(title: "Stay awake for")
    static let awakeDisplay = Self(title: "Keep the display on too")
    static let battery = Self(title: "On battery")
    static let volume = Self(title: "Volume")
    static let quietFocus = Self(title: "Quiet during Focus")
    static let playSounds = Self(title: "Play")
    static let soundsFolder = Self(
        title: "Your sounds folder", description: "Adds your audio files to each sound's menu.")
    static let history = Self(
        title: "Include tasks from outside Native",
        description: "Earlier conversations your agents kept on their own. Native only reads them.")
    static let lightTone = Self(title: "Light mode", description: "Paper is crisp white; Wool is warmer.")
    static let darkTone = Self(
        title: "Dark mode", description: "Standard is a deep gray; True Black is for OLED screens.")
    static let appIcon = Self(title: "App icon", description: "In the Dock and the app switcher.")
    static let shell = Self(title: "Shell", description: "Loads your shell profile. New tabs use it.")
    static let scrollback = Self(title: "Scrollback", description: "Lines kept above the screen, in new terminals.")
    static let taskTitles = Self(title: "Task titles", description: "Named from your first message.")
    static let branchNames = Self(title: "Branch names", description: "From the task's title, like fix-login-bug.")
    static let commitMessages = Self(title: "Commit messages", description: "Drafted when you commit.")
    static let commitGrouping = Self(
        title: "Splitting into commits", description: "How Smart Commit groups your changes.")
    static let prDrafts = Self(title: "Pull requests", description: "The title and description of a new pull request.")
    static let askLines = Self(
        title: "Questions about lines", description: "When you select lines in a pull request and ask an agent.")
    static let askPR = Self(
        title: "Questions about a pull request", description: "When you ask in a pull request's panel.")
}
