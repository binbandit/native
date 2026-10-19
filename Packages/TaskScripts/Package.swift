// swift-tools-version: 6.2
import PackageDescription

// Task scripts: the user's and the repository's scripts that run when a task's worktree is made or
// removed, when a task starts or is deleted, and when a turn ends. Which scripts run, what they're
// told and how they run, without UI (docs/scripts.md).
let package = Package(
    name: "TaskScripts",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TaskScripts", targets: ["TaskScripts"])
    ],
    dependencies: [
        // Scripts run through a `CommandRunner`, on whichever host owns the project.
        .package(path: "../Exec")
    ],
    targets: [
        .target(name: "TaskScripts", dependencies: [.product(name: "Exec", package: "Exec")]),
        .testTarget(name: "TaskScriptsTests", dependencies: ["TaskScripts"]),
    ]
)
