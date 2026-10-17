import Foundation

/// An app a task's folder can be opened in: an editor or IDE, a terminal, a git client or Finder.
/// The catalog lists every app Native knows how to hand a folder to; `OpenInApp` is one of them
/// that's installed.
nonisolated struct OpenInTarget: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case editor, terminal, gitClient, fileManager
    }

    /// How the app is handed the folder.
    enum Launch: Hashable, Sendable {
        /// As a document, like `open -a <app> <folder>`. Editors, IDEs and git clients open it as a
        /// project; Terminal, iTerm2, Ghostty and Warp open a window in it; Finder shows it.
        case document
        /// A new process whose arguments end with the folder's path, for terminals that ignore
        /// open-document events and take a working directory on the command line instead.
        case arguments([String])
    }

    /// Persisted as the user's default, so it never changes once shipped.
    let id: String
    /// Every bundle identifier the app ships under, preferred first.
    let bundleIdentifiers: [String]
    let kind: Kind
    var launch = Launch.document
}

extension OpenInTarget {
    /// Every known app, grouped by kind. Within a group the most widely used come first, so on first
    /// run the first installed one is the likeliest default: an editor if there is any, Xcode only
    /// when nothing else is installed (most Macs with developer tools have it), and Finder last.
    static let catalog: [OpenInTarget] = editors + terminals + gitClients + [finder]

    static let finder = OpenInTarget(id: "finder", bundleIdentifiers: ["com.apple.finder"], kind: .fileManager)

    private static let editors: [OpenInTarget] = [
        .init(id: "cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], kind: .editor),
        .init(id: "vscode", bundleIdentifiers: ["com.microsoft.VSCode"], kind: .editor),
        .init(id: "vscode-insiders", bundleIdentifiers: ["com.microsoft.VSCodeInsiders"], kind: .editor),
        .init(id: "zed", bundleIdentifiers: ["dev.zed.Zed"], kind: .editor),
        .init(id: "zed-preview", bundleIdentifiers: ["dev.zed.Zed-Preview"], kind: .editor),
        .init(id: "zed-nightly", bundleIdentifiers: ["dev.zed.Zed-Nightly"], kind: .editor),
        .init(id: "windsurf", bundleIdentifiers: ["com.exafunction.windsurf"], kind: .editor),
        .init(id: "antigravity", bundleIdentifiers: ["com.google.antigravity-ide"], kind: .editor),
        .init(id: "vscodium", bundleIdentifiers: ["com.vscodium"], kind: .editor),
        .init(id: "sublime-text", bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"], kind: .editor),
        .init(id: "nova", bundleIdentifiers: ["com.panic.Nova"], kind: .editor),
        .init(id: "bbedit", bundleIdentifiers: ["com.barebones.bbedit"], kind: .editor),
        .init(id: "textmate", bundleIdentifiers: ["com.macromates.TextMate"], kind: .editor),
        .init(id: "intellij-idea", bundleIdentifiers: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"], kind: .editor),
        .init(id: "pycharm", bundleIdentifiers: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], kind: .editor),
        .init(id: "webstorm", bundleIdentifiers: ["com.jetbrains.WebStorm"], kind: .editor),
        .init(id: "goland", bundleIdentifiers: ["com.jetbrains.goland"], kind: .editor),
        .init(id: "rustrover", bundleIdentifiers: ["com.jetbrains.rustrover"], kind: .editor),
        .init(id: "clion", bundleIdentifiers: ["com.jetbrains.CLion"], kind: .editor),
        .init(id: "phpstorm", bundleIdentifiers: ["com.jetbrains.PhpStorm"], kind: .editor),
        .init(id: "rubymine", bundleIdentifiers: ["com.jetbrains.rubymine"], kind: .editor),
        .init(id: "rider", bundleIdentifiers: ["com.jetbrains.rider"], kind: .editor),
        .init(id: "android-studio", bundleIdentifiers: ["com.google.android.studio"], kind: .editor),
        .init(id: "fleet", bundleIdentifiers: ["com.jetbrains.fleet"], kind: .editor),
        .init(id: "xcode", bundleIdentifiers: ["com.apple.dt.Xcode"], kind: .editor),
    ]

    private static let terminals: [OpenInTarget] = [
        .init(id: "ghostty", bundleIdentifiers: ["com.mitchellh.ghostty"], kind: .terminal),
        .init(id: "iterm", bundleIdentifiers: ["com.googlecode.iterm2"], kind: .terminal),
        .init(id: "warp", bundleIdentifiers: ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview"], kind: .terminal),
        // With `--single-instance`, a running kitty opens the window and the new process exits.
        .init(
            id: "kitty",
            bundleIdentifiers: ["net.kovidgoyal.kitty"],
            kind: .terminal,
            launch: .arguments(["--single-instance", "--directory"])
        ),
        // `start` opens the window in the running WezTerm when there is one.
        .init(
            id: "wezterm",
            bundleIdentifiers: ["com.github.wez.wezterm"],
            kind: .terminal,
            launch: .arguments(["start", "--cwd"])
        ),
        .init(
            id: "alacritty",
            bundleIdentifiers: ["org.alacritty"],
            kind: .terminal,
            launch: .arguments(["--working-directory"])
        ),
        .init(id: "terminal", bundleIdentifiers: ["com.apple.Terminal"], kind: .terminal),
    ]

    private static let gitClients: [OpenInTarget] = [
        .init(id: "tower", bundleIdentifiers: ["com.fournova.Tower3", "com.fournova.Tower2"], kind: .gitClient),
        .init(id: "github-desktop", bundleIdentifiers: ["com.github.GitHubClient"], kind: .gitClient),
        .init(id: "fork", bundleIdentifiers: ["com.DanPristupov.Fork"], kind: .gitClient),
        .init(id: "sourcetree", bundleIdentifiers: ["com.torusknot.SourceTreeNotMAS"], kind: .gitClient),
        .init(id: "sublime-merge", bundleIdentifiers: ["com.sublimemerge"], kind: .gitClient),
    ]
}
