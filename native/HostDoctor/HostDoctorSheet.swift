import NativeHostClient
import NativeHostProtocol
import SwiftUI

/// The host doctor's checks for one host (docs/droids.md): what its agents need, grouped, each
/// with what was found and the command or setting that fixes it. Read-only: it never changes the
/// host. Takes any host's client, so Settings can open it for this Mac or for a droid.
///
///     .sheet(isPresented: $isChecking) { HostDoctorSheet(hostName: "This Mac", client: client) }
struct HostDoctorSheet: View {
    /// Off until it's verified in the running app: `-NativeHostDoctor YES` shows Check This Mac….
    static var isAvailable: Bool {
        UserDefaults.standard.object(forKey: "NativeHostDoctor") as? Bool ?? false
    }

    @State private var model: HostDoctorModel
    @State private var didCopy = false

    @Environment(\.dismiss) private var dismiss

    init(hostName: String, client: NativeHostClient) {
        _model = State(initialValue: HostDoctorModel(hostName: hostName, client: client))
    }

    init(model: HostDoctorModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SeparatorLine()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SeparatorLine()
            footer
        }
        .frame(
            minWidth: HostDoctorMetrics.minWidth, idealWidth: HostDoctorMetrics.width,
            minHeight: HostDoctorMetrics.minHeight, idealHeight: HostDoctorMetrics.height
        )
        .background(.dsBackground)
        .task { await model.check() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text("Check \(model.hostName)")
                .font(.dsHeadline)
                .foregroundStyle(.dsTextPrimary)
            Text(summary)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
    }

    private var summary: String {
        guard let report = model.report else {
            return "What agents need to run here on their own. Checking changes nothing."
        }
        let problems = report.checks.count { $0.status >= .warning }
        let checked = "Checked at \(report.checkedAt.formatted(date: .omitted, time: .shortened))."
        return problems == 0
            ? "Everything looks ready. \(checked)"
            : "\(problems) \(problems == 1 ? "thing" : "things") to look at. \(checked)"
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .checking:
            LoadingStateView("Checking \(model.hostName)…")
        case .failed(let message):
            ErrorState(
                "Couldn't check \(model.hostName)",
                suggestion: "Its background host has to be running and reachable.",
                details: message,
                primary: .init("Try Again") { Task { await model.check() } },
                layout: .pane)
        case .checked(let report):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.xl) {
                    if !report.isHostRunning {
                        NoticeBanner(
                            tone: .info, systemImage: "moon.zzz", title: "The background host isn't running",
                            detail: "These checks ran without it, so the agents it runs aren't listed.")
                    }
                    ForEach(report.groups.map { $0.group }, id: \.self) { section in
                        group(section, checks: report.checks.filter { $0.group == section })
                    }
                }
                .padding(DS.Space.xl)
            }
        }
    }

    private func group(_ group: HostDoctorCheck.Group, checks: [HostDoctorCheck]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(.dsCalloutMedium)
                .foregroundStyle(.dsTextPrimary)
            if group == .unattended {
                Text("Only matters for a Mac that runs agents with nobody at it, like a Mac mini.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .padding(.top, DS.Space.xxs)
            }
            ForEach(checks) { check in
                HostDoctorCheckRow(check: check)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            Button(didCopy ? "Copied" : "Copy as Text") {
                guard let report = model.report else { return }
                DSPasteboard.copy(report.text)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopy = false
                }
            }
            .buttonStyle(.ds(.secondary, size: .medium))
            .disabled(model.report == nil)
            Button("Check Again") {
                Task { await model.check() }
            }
            .buttonStyle(.ds(.secondary, size: .medium))
            .disabled(model.report == nil)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.ds(.primary, size: .medium))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
    }
}

#if DEBUG
#Preview("Check This Mac") {
    DSPreviewPair {
        HostDoctorSheet(model: HostDoctorModel(hostName: "This Mac") { HostDoctorFixtures.report })
            .frame(width: HostDoctorMetrics.width, height: HostDoctorMetrics.height)
    }
}

#Preview("Check This Mac - Couldn't check") {
    DSPreviewPair {
        HostDoctorSheet(model: HostDoctorModel(hostName: "elara") { throw CocoaError(.fileReadNoPermission) })
            .frame(width: HostDoctorMetrics.width, height: HostDoctorMetrics.minHeight)
    }
}

nonisolated enum HostDoctorFixtures {
    static let report = HostDoctorReport(
        machineName: "elara", checkedAt: .now, isHostRunning: true,
        checks: [
            HostDoctorCheck(
                id: "host.loginItem", group: .host, title: "Starts at login", status: .ok,
                detail: "Registered as a login item, so it starts at every login"),
            HostDoctorCheck(
                id: "host.keepAwake", group: .host, title: "Keep awake", status: .ok,
                detail: "Keeping awake while 2 agents work"),
            HostDoctorCheck(
                id: "agents.node", group: .agents, title: "Node.js", status: .ok,
                detail: "v22.11.0 at /opt/homebrew/bin/node"),
            HostDoctorCheck(
                id: "agents.codex", group: .agents, title: "Codex", status: .failed,
                detail: "codex isn't on your login shell's PATH",
                fix: HostDoctorFix(command: "npm install -g @openai/codex")),
            HostDoctorCheck(
                id: "tools.gh.auth", group: .tools, title: "GitHub sign-in", status: .warning,
                detail: "Not signed in; Native can't open pull requests",
                fix: HostDoctorFix(
                    setting: "Sign in over SSH; it shows a code to enter in a browser", command: "gh auth login")),
            HostDoctorCheck(
                id: "system.disk", group: .system, title: "Free disk space", status: .ok, detail: "412 GB free"),
            HostDoctorCheck(
                id: "unattended.sleep", group: .unattended, title: "Stays awake", status: .warning,
                detail: "Sleeps after 10 minutes idle, even while agents work",
                fix: HostDoctorFix(
                    setting: "System Settings ▸ Energy ▸ Prevent automatic sleeping when the display is off",
                    command: "sudo pmset -a sleep 0")),
        ])
}
#endif
