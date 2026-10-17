import Git
import SwiftUI

/// How a task's new worktree is getting set up, above the task's conversation: the setup script
/// running, how it went, and on failure its output with Retry and Open Script. Shows nothing for
/// tasks without a setup run.
struct GitTaskSetupBanner: View {
    let store: GitStore
    let folder: URL

    @State private var showsOutput = false
    @State private var isEditingScript = false

    var body: some View {
        if let run = store.setupRuns[folder.standardizedFileURL] {
            VStack(spacing: 0) {
                content(run)
                    .padding(.leading, DS.Space.lg)
                    .padding(.trailing, DS.Space.xs)
                    .padding(.vertical, DS.Space.md)
                    .background(run.isFailure ? Color.dsDanger.opacity(0.06) : .clear)
                SeparatorLine()
            }
            .sheet(isPresented: $isEditingScript) {
                GitSetupScriptEditor(settings: store.settings, root: run.projectRoot)
            }
        }
    }

    private func content(_ run: GitSetupRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            glyph(run)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title(run))
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let message = message(run) {
                    Text(message)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
                if showsOutput || run.isFailure, let output = output(run) {
                    CappedHeightScrollView(maxHeight: GitMetrics.noticeDetailMaxHeight) {
                        Text(output)
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.sm)
                    }
                    .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                }
                actions(run)
                    .padding(.top, DS.Space.xxs)
            }
            .tracking(DS.Tracking.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            if run.state != .running {
                IconButton("Dismiss", systemImage: "xmark") { store.dismissSetup(in: folder) }
                    .dsHitTarget(DS.Size.controlXS)
            }
        }
    }

    @ViewBuilder private func glyph(_ run: GitSetupRun) -> some View {
        if run.state == .running {
            DotGridLoader(pattern: .settingUp)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: GitMetrics.loaderSmall, height: GitMetrics.loaderSmall)
        } else {
            Image(systemName: run.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(run.isFailure ? Color.dsDanger : .dsSuccess)
        }
    }

    @ViewBuilder private func actions(_ run: GitSetupRun) -> some View {
        HStack(spacing: DS.Space.sm) {
            if run.isFailure {
                Button("Retry") { store.retrySetup(in: folder) }
                    .buttonStyle(.ds(.secondary))
                Button("Open Script") { isEditingScript = true }
                    .buttonStyle(.ds(.ghost))
            } else if run.state != .running, output(run) != nil {
                Button(showsOutput ? "Hide Output" : "Show Output") { showsOutput.toggle() }
                    .buttonStyle(.ds(.ghost))
            }
        }
    }

    // MARK: - Text

    private func title(_ run: GitSetupRun) -> String {
        switch run.state {
        case .running: "Setting up the worktree"
        case .failed: "The worktree couldn't be set up"
        case .finished(let result) where result.timedOut: "The setup script ran too long"
        case .finished(let result) where result.succeeded:
            "Worktree set up in \(result.duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))"
        case .finished(let result): "The setup script failed with exit code \(result.exitCode ?? 1)"
        }
    }

    private func message(_ run: GitSetupRun) -> String? {
        var parts: [String] = []
        switch run.state {
        case .running:
            parts.append(
                "Running \(run.projectRoot.lastPathComponent)'s setup script. You can start working; the agent sees the files as they appear."
            )
        case .failed(let reason):
            parts.append(reason)
        case .finished(let result) where result.timedOut:
            parts.append(
                "It was stopped after \(GitStore.setupTimeout.formatted(.units(allowed: [.minutes], width: .wide))). The task can still run; retry once the script is faster."
            )
        case .finished(let result) where !result.succeeded:
            parts.append(
                "The task can still run, but may be missing what the script installs. Fix the script, then retry.")
        case .finished:
            break
        }
        if !run.copiedFiles.isEmpty {
            parts.append(
                "Copied \(run.copiedFiles.count == 1 ? run.copiedFiles[0] : "\(run.copiedFiles.count) env files") from the project."
            )
        }
        if let copyFailure = run.copyFailure {
            parts.append("Couldn't copy the project's env files: \(copyFailure)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func output(_ run: GitSetupRun) -> String? {
        guard case .finished(let result) = run.state else { return nil }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}
