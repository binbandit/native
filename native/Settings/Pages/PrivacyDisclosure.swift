import SwiftUI

/// Settings ▸ Privacy's promise in full: everything Native's telemetry can carry, side by side with
/// what it never does. Information, so it's a note rather than rows. Keep both lists in step with
/// `TelemetryEvent`, `TelemetryResource` and `SentryPrivacy`.
struct PrivacyDisclosure: View {
    /// When the lists apply, which depends on the build and the organization's policy.
    let scope: String

    static let sent = [
        "Which features you use",
        "How long Native takes to launch",
        "When Native stops responding, and for how long",
        "Crash reports: the kind of error and where in Native's code, as memory addresses",
        "Which agents start sessions, and their versions",
        "The app and macOS versions, and a random ID for this installation",
    ]

    static let neverSent = [
        "Prompts, replies and transcripts",
        "Code and file contents",
        "File and folder names and paths",
        "Commands, and tool input and output",
        "Project and account names",
        "Anything you type",
    ]

    var body: some View {
        SettingsNote("What Native sends") {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text(scope)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DS.Space.xxxl) { lists }
                    VStack(alignment: .leading, spacing: DS.Space.xl) { lists }
                }
            }
        }
    }

    @ViewBuilder private var lists: some View {
        PrivacyList(title: "Sent", items: Self.sent)
        PrivacyList(title: "Never sent", items: Self.neverSent)
    }
}

/// One column: a heading and its items, each after a dot.
private struct PrivacyList: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(SettingsTextStyle.bodyMedium.font)
                .foregroundStyle(.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                    Circle()
                        .fill(.dsTextTertiary)
                        .frame(width: PrivacyMetrics.bullet, height: PrivacyMetrics.bullet)
                        // On the middle of the lowercase letters.
                        .alignmentGuide(.firstTextBaseline) { $0.height / 2 + PrivacyMetrics.bulletRise }
                        .accessibilityHidden(true)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minWidth: PrivacyMetrics.columnMinWidth, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private enum PrivacyMetrics {
    static let bullet: CGFloat = 4
    /// Half the x-height of the 14pt body text.
    static let bulletRise: CGFloat = 4
    /// Below this the two lists stack.
    static let columnMinWidth: CGFloat = 260
}

#Preview("Privacy disclosure") {
    DSPreviewPair {
        PrivacyDisclosure(scope: "Only while sharing is on, and only this:")
            .frame(width: 720)
            .padding(DS.Space.xl)
    }
}
