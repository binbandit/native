import AppKit
import Foundation

// Quits the copy of Native at the path given, the way ⌘Q does, before scripts/dev/install.sh replaces
// it: the app saves its state and its background host keeps every agent working. Copies elsewhere
// (test instances share the name) are left alone. If it doesn't quit (a dialog holds it), this fails
// and the install stops, rather than forcing it and losing what it hasn't saved.
//
//   swift scripts/dev/quit-for-install.swift ~/Applications/Native.app

guard CommandLine.arguments.count == 2 else {
    fputs("usage: quit-for-install.swift <app bundle>\n", stderr)
    exit(2)
}
// A directory URL, as bundle URLs are: with its trailing slash, so the two compare equal.
let target = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory).standardizedFileURL
    .resolvingSymlinksInPath()
let running = NSWorkspace.shared.runningApplications.filter {
    $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == target
}
for app in running where !app.terminate() {
    fputs("Couldn't ask \(target.lastPathComponent) to quit; it's still running.\n", stderr)
    exit(1)
}
// Polled by pid: a command-line tool doesn't hear NSRunningApplication's `isTerminated` change.
var quitting = Set(running.map(\.processIdentifier))
let deadline = Date.now.addingTimeInterval(30)
while !quitting.isEmpty, Date.now < deadline {
    Thread.sleep(forTimeInterval: 0.1)
    quitting = quitting.filter { kill($0, 0) == 0 }
}
guard quitting.isEmpty else {
    fputs(
        "\(target.lastPathComponent) didn't quit within 30 seconds (is a dialog open?). Nothing was replaced.\n", stderr
    )
    exit(1)
}
