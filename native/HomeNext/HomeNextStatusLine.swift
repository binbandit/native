import NativePolicy
import SwiftUI

struct HomeNextStatusLine: View {
    let tasks: [HomeNextTask]
    /// "While you were away, …", when the user chose to see it and something happened.
    var away: String?
    @Environment(PolicyCenter.self) private var policy: PolicyCenter?

    var body: some View {
        let working = tasks.filter { $0.status.isActive }
        let local = working.filter { $0.host == nil }.count
        let remote = working.count - local
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            if !working.isEmpty {
                Text(status(working: working.count, local: local, remote: remote))
                    .foregroundStyle(.dsTextSecondary)
            }
            if let away {
                Text(away).foregroundStyle(.dsTextTertiary).accessibilityIdentifier("home-next-away")
            }
            if let policy = policy?.policy, !policy.remoteHostsEnabled, policy.isManaged(.remoteHostsEnabled) {
                Text("Other Macs are turned off by \(policy.organizationName ?? "your organization").")
                    .foregroundStyle(.dsTextTertiary)
            } else if let policy = policy?.policy, !policy.managedKeys.isEmpty {
                Text("Managed by \(policy.organizationName ?? "your organization").")
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        .font(.dsBody)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("home-next-status")
    }

    private func status(working: Int, local: Int, remote: Int) -> String {
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
#Preview("Next status - While you were away") {
    DSPreviewPair {
        HomeNextStatusLine(
            tasks: [],
            away: HomeNextAway(
                start: .now.addingTimeInterval(-8_160), end: .now.addingTimeInterval(-120), finished: 2, asked: 3,
                failed: 1
            ).sentence
        )
        .padding(DS.Space.xxl)
    }
}
#Preview("Next status - Managed") { HomeNextPreviewFixtures.page(.managed) }
#endif
