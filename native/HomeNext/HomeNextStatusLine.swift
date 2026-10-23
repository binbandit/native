import SwiftUI

struct HomeNextStatusLine: View {
    let tasks: [HomeNextTask]

    var body: some View {
        let working = tasks.filter { $0.status.isActive }
        let local = working.filter { $0.host == nil }.count
        let remote = working.count - local
        Text(status(working: working.count, local: local, remote: remote))
            .font(.dsBody).foregroundStyle(.dsTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home-next-status")
    }

    private func status(working: Int, local: Int, remote: Int) -> String {
        if working == 0 { return "No tasks are running." }
        let places = remote > 0 ? ", \(remote) on other hosts" : ""
        #if os(macOS)
        let lid =
            local > 0
            ? "Closing the lid pauses \(local) \(local == 1 ? "task" : "tasks")." : "Safe to close the lid."
        return "\(working) working\(places). \(lid)"
        #else
        return "\(working) working\(places)."
        #endif
    }
}

#if DEBUG
#Preview("Next status - No work") {
    DSPreviewPair { HomeNextStatusLine(tasks: []).padding(DS.Space.xxl) }
}
#endif
