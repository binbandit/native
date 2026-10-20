#if DEBUG
import Foundation
import NativeTelemetry
import SwiftUI

/// Settings previews' data, and pages framed the way the Settings screen shows them.
enum SettingsPreviewFixtures {
    /// The agent extensions and a few of Native's own, without the ones that watch the clock or the
    /// network as soon as they exist.
    static func registry() -> PluginRegistry {
        PluginRegistry(builtIns: [
            BuiltInPlugins.claudeCode, BuiltInPlugins.codex, BuiltInPlugins.cursor, BuiltInPlugins.openCode,
            OnDeviceTitlesPlugin(), SoundsPlugin(), MCPServersPlugin(), SkillsPlugin(), OrchestrationPlugin(),
        ])
    }

    static func folders(readers: [AgentDefinition]) -> [SettingsFolder] {
        let claude = readers.filter { $0.id.rawValue == "claude-code" }
        return [
            SettingsFolder(
                scope: .project, section: "This project · native", label: ".claude/skills",
                paths: ["/Users/preview/Developer/native/.claude/skills"], readers: claude, exists: true, itemCount: 3),
            SettingsFolder(
                scope: .project, section: "This project · native", label: ".agents/skills",
                paths: ["/Users/preview/Developer/native/.agents/skills"], readers: readers, exists: false,
                itemCount: 0),
            SettingsFolder(
                scope: .user, section: "Your user folder", label: "~/.claude/skills",
                paths: ["/Users/preview/.claude/skills"], readers: claude, exists: true, itemCount: 12,
                problem: "review-pr/SKILL.md has no description, so agents can’t tell when to use it"),
            SettingsFolder(
                scope: .user, section: "Your user folder", label: "~/.codex/skills",
                paths: ["/Users/preview/.codex/skills"], readers: readers.filter { $0.id.rawValue == "codex" },
                exists: true, itemCount: 4),
        ]
    }

    /// What Settings ▸ Privacy's log lists: two batches, as sent.
    static let sentLog: [TelemetrySentLog.Entry] = {
        let resource = TelemetryResource(
            installationID: UUID(), appVersion: TelemetryVersion("1.4.0"), osVersion: TelemetryVersion("27.1"))
        let batches: [[TelemetryEvent]] = [
            [.appLaunched(launchDuration: .milliseconds(412)), .featureUsed(.settings)],
            [
                .sessionStarted(agent: .claudeCode, agentVersion: TelemetryVersion("0.93.0")),
                .featureUsed(.queuedMessage), .featureUsed(.planMode),
            ],
        ]
        return batches.enumerated().compactMap { index, events in
            let sent = SentEntry(
                date: .now.addingTimeInterval(Double(index - 2) * 3600), destination: .native, resource: resource,
                records: events.map { TelemetryRecord($0, at: .now.addingTimeInterval(Double(index - 2) * 3600)) })
            guard let data = try? JSONEncoder().encode(sent) else { return nil }
            return try? JSONDecoder().decode(TelemetrySentLog.Entry.self, from: data)
        }
    }()

    /// `TelemetrySentLog.Entry` keeps its initializer to the package; this encodes to the same shape.
    private struct SentEntry: Encodable {
        var id = UUID()
        let date: Date
        let destination: TelemetryDestinationID
        let resource: TelemetryResource
        let records: [TelemetryRecord]
    }
}

extension View {
    /// A settings page's content, padded and sized as the Settings screen shows it.
    func settingsPreviewPage(width: CGFloat = 720) -> some View {
        padding(.horizontal, SettingsMetrics.pageInset)
            .padding(.top, SettingsMetrics.pageTopInset)
            .padding(.bottom, SettingsMetrics.pageBottomInset)
            .frame(width: width)
    }
}
#endif
