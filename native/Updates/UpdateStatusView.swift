import SwiftUI

/// Every update state in one place: what's happening, what the user can do, and what happens next.
/// Settings ▸ Updates and the Software Update window both show it, so each state reads the same.
struct UpdateStatusView: View {
    let controller: UpdateController

    @Environment(\.openURL) private var openURL
    @State private var isConfirmingRestart = false

    var body: some View {
        content
            .updateRestartConfirmation(controller, isPresented: $isConfirmingRestart)
    }

    /// A failure is its own outlined notice; every other state sits on a card.
    @ViewBuilder
    private var content: some View {
        if case .failed(let failure) = controller.state {
            failed(failure)
        } else {
            Card { status }
        }
    }

    private var status: some View {
        Group {
            switch controller.state {
            case .idle:
                idle
            case .checking:
                progress(
                    "Checking for updates…", detail: "Looking at the \(controller.channel.title) channel on GitHub.")
            case .upToDate(let checkedAt):
                upToDate(checkedAt: checkedAt)
            case .available(let release):
                available(release)
            case .downloading(let release, let fraction):
                transferring(
                    "Downloading Native \(release.version)…", release: release, fraction: fraction, canCancel: true)
            case .preparing(let release, let fraction):
                transferring(
                    "Preparing Native \(release.version)…", release: release, fraction: fraction, canCancel: false)
            case .ready(let release):
                ready(release)
            case .installing(let release):
                progress("Installing Native \(release.version)…", detail: "Native reopens in a moment.")
            case .failed:
                EmptyView()
            case .unavailable(let reason):
                unavailable(reason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.dsStandard, value: controller.state)
    }

    // MARK: - States

    private var idle: some View {
        UpdateStatusRow(
            symbol: "arrow.triangle.2.circlepath", tint: .dsTextSecondary,
            title: controller.automaticallyChecks ? "Native checks for updates every day" : "Automatic checks are off",
            detail: lastCheckedText
        ) {
            Button("Check Now", action: controller.checkForUpdates)
                .buttonStyle(.ds(.secondary))
        }
    }

    private func upToDate(checkedAt: Date) -> some View {
        UpdateStatusRow(
            symbol: "checkmark.circle.fill", tint: .dsSuccess,
            title: "Native is up to date",
            detail: "Version \(controller.current.version) is the newest on the \(controller.channel.title) channel. "
                + "Checked \(Self.checkedAgo(checkedAt))."
        ) {
            Button("Check Again", action: controller.checkForUpdates)
                .buttonStyle(.ds(.ghost))
        }
    }

    private func available(_ release: UpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            UpdateStatusRow(
                symbol: "arrow.down.circle.fill", tint: .dsAccent,
                title: "Native \(release.version) is available",
                detail: releaseFacts(release, extra: "You have \(controller.current.version).")
            ) {
                Button("Skip This Version", action: controller.skipVersion)
                    .buttonStyle(.ds(.ghost))
                    .disabled(release.isCritical)
                Button("Update", action: requestInstall)
                    .buttonStyle(.ds(.primary))
            }
            notes(release)
        }
    }

    private func transferring(_ title: String, release: UpdateRelease, fraction: Double?, canCancel: Bool) -> some View
    {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            UpdateStatusRow(
                symbol: "arrow.down.circle", tint: .dsAccent, title: title,
                detail: transferDetail(release: release, fraction: fraction)
            ) {
                if canCancel {
                    Button("Cancel", action: controller.cancelDownload)
                        .buttonStyle(.ds(.ghost))
                }
            }
            ProgressView(value: fraction ?? 0)
                .progressViewStyle(.linear)
                .tint(.dsAccent)
                .opacity(fraction == nil ? 0.4 : 1)
                .accessibilityLabel(title)
        }
    }

    private func ready(_ release: UpdateRelease) -> some View {
        let waiting = controller.pendingRestart == .whenTasksFinish
        let context = controller.restartContext()
        let title = waiting ? "Native restarts when your tasks finish" : "Native \(release.version) is ready to install"
        let detail = [
            waiting ? "Native \(release.version) is downloaded." : "It installs when you quit Native, or restart now.",
            context.summary,
        ].compactMap(\.self).joined(separator: " ")
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            UpdateStatusRow(symbol: "checkmark.seal.fill", tint: .dsAccent, title: title, detail: detail) {
                if waiting {
                    Button("Don't Restart", action: controller.cancelPendingRestart)
                        .buttonStyle(.ds(.ghost))
                    Button("Restart Now") { controller.installUpdate(.now) }
                        .buttonStyle(.ds(.primary))
                } else {
                    Button("Restart to Update", action: requestInstall)
                        .buttonStyle(.ds(.primary))
                }
            }
            notes(release)
        }
    }

    private func failed(_ failure: UpdateFailure) -> some View {
        ErrorState(
            failure.title,
            recovery: failure.recovery,
            suggestion: failure.suggestion,
            details: failure.details,
            primary: failure.canRetry
                ? .init("Try Again", perform: controller.checkForUpdates)
                : controller.current.allReleasesURL.map { url in .init("Open GitHub Releases") { openURL(url) } },
            secondary: failure.canRetry
                ? controller.current.allReleasesURL.map { url in .init("Open GitHub Releases") { openURL(url) } }
                : nil
        )
    }

    private func unavailable(_ reason: UpdateUnavailableReason) -> some View {
        let (title, detail): (String, String) =
            switch reason {
            case .developmentBuild:
                (
                    "Updates are off in development builds",
                    "This build runs from source, so it has no update feed: a release would replace it. Pull and rebuild to get new changes."
                )
            case .notConfigured:
                (
                    "Updates aren't set up for this build",
                    "It has no update feed or signing key, so it can't verify an update. Install a release from GitHub to get updates."
                )
            case .unsupportedPlatform:
                ("Updates come from the App Store", "On iPad, Native updates through the App Store or TestFlight.")
            case .updaterFailed(let message):
                (
                    "Native can't check for updates",
                    "The updater didn't start: \(message) Install the latest release from GitHub to fix it."
                )
            }
        return UpdateStatusRow(symbol: "minus.circle", tint: .dsTextTertiary, title: title, detail: detail) {
            if let url = controller.current.allReleasesURL {
                Button("Open GitHub Releases") { openURL(url) }
                    .buttonStyle(.ds(.secondary))
            }
        }
    }

    private func progress(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            DotGridLoader(pattern: .waiting)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                .padding(.top, DS.Space.xxs)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
                Text(detail).font(.dsBody).foregroundStyle(.dsTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func notes(_ release: UpdateRelease) -> some View {
        if let notes = release.notes, !notes.isEmpty {
            UpdateReleaseNotesView(markdown: notes)
        }
    }

    // MARK: - Text

    private var lastCheckedText: String {
        guard let date = controller.lastChecked else { return "It hasn't checked yet." }
        return "Last checked \(Self.checkedAgo(date))."
    }

    /// "just now" or "5m ago", from the app's one age format.
    private static func checkedAgo(_ date: Date) -> String {
        let age = DSFormat.compactAge(date, now: .now)
        return age == "now" ? "just now" : "\(age) ago"
    }

    private func releaseFacts(_ release: UpdateRelease, extra: String) -> String {
        var facts: [String] = []
        if release.channel == "beta" { facts.append("Beta") }
        if let date = release.date { facts.append("Released \(date.formatted(date: .abbreviated, time: .omitted))") }
        if let size = release.size { facts.append(DSFormat.memory(size)) }
        let line = facts.isEmpty ? "" : facts.joined(separator: " · ") + ". "
        let critical = release.isCritical ? " This update fixes a serious problem; please install it." : ""
        return line + extra + critical
    }

    private func transferDetail(release: UpdateRelease, fraction: Double?) -> String {
        guard let fraction else { return "Starting…" }
        let done = DSFormat.percent(fraction)
        if let size = release.size {
            return "\(done) of \(DSFormat.memory(size))"
        }
        return done
    }

    private func requestInstall() {
        if controller.restartContext().needsConfirmation {
            isConfirmingRestart = true
        } else {
            controller.installUpdate(.now)
        }
    }
}

/// A state's glyph, title, supporting line and actions.
private struct UpdateStatusRow<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: symbol)
                .font(.system(size: DS.Size.statusGlyph))
                .foregroundStyle(tint)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                .padding(.top, DS.Space.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
                if let detail {
                    Text(detail)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: DS.Space.sm) {
                actions
            }
            .fixedSize()
        }
    }
}

#if DEBUG
#Preview("Update states") {
    let samples = [
        "idle", "checking", "upToDate", "available", "downloading", "preparing", "ready", "readyWaiting",
        "installing", "failedOffline", "failedSecurity", "developmentBuild", "notConfigured",
    ]
    ScrollView {
        DSPreviewPair {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                ForEach(samples, id: \.self) { sample in
                    UpdateStatusView(controller: .preview(sample))
                }
            }
            .frame(width: 560)
        }
    }
}
#endif
