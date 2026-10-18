import NativeHostProtocol
import SwiftUI

/// A host's Native version and updates (`docs/releasing.md`, "Remote updates"): what's new, Update
/// Now (or a clear choice when tasks are running), progress through the restart, and a failure or
/// rollback in plain words. When this phone may not install, it says why instead of hiding it.
struct HostUpdateSection: View {
    let host: HostConnection

    @State private var failure: String?
    @State private var isConfirmingInterrupt = false
    @State private var showsNotes = false

    var body: some View {
        Section("Native") {
            if let status = host.update {
                content(status)
            } else if host.phase.isConnected {
                Text("Checking what \(host.name) runs…").foregroundStyle(.dsTextSecondary)
            } else {
                Text("Shows once \(host.name) is connected.").foregroundStyle(.dsTextSecondary)
            }
            if let failure {
                Text(failure).font(CompanionType.caption).foregroundStyle(.dsDanger)
            }
        }
        .confirmationDialog(
            "Interrupt \(host.update?.workingSessions ?? 0) running task\(host.update?.workingSessions == 1 ? "" : "s")?",
            isPresented: $isConfirmingInterrupt, titleVisibility: .visible
        ) {
            Button("Install Now, Interrupt Tasks", role: .destructive) { install(.now) }
            Button("Install When Idle") { install(.idle) }
        } message: {
            Text("\(host.name) restarts to update. Interrupted tasks are told what happened and pick up where they left off.")
        }
    }

    @ViewBuilder
    private func content(_ status: HostUpdateStatus) -> some View {
        LabeledContent("Version", value: "\(status.current.version) (\(status.current.build))")
        if let rollback = status.lastRollback {
            NoticeBanner(
                tone: .warning, title: "Went back to \(rollback.to)",
                detail: "Native \(rollback.from) didn't start properly, so \(host.name) returned to \(rollback.to) at \(rollback.at.formatted(date: .omitted, time: .shortened)). Tasks resumed.")
        }
        switch status.state {
        case .checking:
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .settingUp)
                Text("Checking for updates…").foregroundStyle(.dsTextSecondary)
            }
        case .available, .ready, .downloading:
            if let release = status.available { available(release, status: status) }
        case .installing:
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .settingUp)
                Text("Installing. \(host.name) restarts, and this phone reconnects on its own.").foregroundStyle(.dsTextSecondary)
            }
        case .failed:
            ErrorState(
                "The update didn't install", recovery: "\(host.name) kept running \(status.current.version).",
                suggestion: status.message, primary: status.canInstall ? .init("Try Again") { install(.idle) } : nil)
        case .unavailable:
            Text(status.message ?? "Updates for \(host.name) are managed outside Native.").foregroundStyle(.dsTextSecondary)
        case .upToDate, .idle, .unknown:
            HStack {
                Text(upToDateLine(status)).foregroundStyle(.dsTextSecondary)
                Spacer()
                Button("Check Now") { Task { failure = await host.checkForUpdate() } }
                    .disabled(!host.phase.isConnected)
            }
        }
    }

    @ViewBuilder
    private func available(_ release: HostUpdateStatus.Release, status: HostUpdateStatus) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Update available · \(release.version)")
                .font(CompanionType.bodyMedium)
                .foregroundStyle(release.critical ? .dsAttention : .dsAccentText)
            if let size = release.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(CompanionType.caption).foregroundStyle(.dsTextTertiary)
            }
        }
        if let notes = release.notes, !notes.isEmpty {
            DisclosureGroup("What's New", isExpanded: $showsNotes) {
                MarkdownView(notes).font(CompanionType.subheadline)
            }
        }
        if let url = release.releaseNotesURL {
            Link("Release Notes", destination: url)
        }
        if status.state == .downloading, let progress = status.progress {
            ProgressView(value: progress) { Text("Downloading").font(CompanionType.caption) }
        }
        if let pending = status.pendingInstall, pending == .idle {
            Text("Installs when \(host.name)'s tasks finish (\(status.workingSessions) running).")
                .font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
        } else if status.canInstall {
            Button(status.workingSessions > 0 ? "Update…" : "Update Now") {
                if status.workingSessions > 0 { isConfirmingInterrupt = true } else { install(.idle) }
            }
            .accessibilityIdentifier("updateNow")
        } else {
            Text("This iPhone can't install updates on \(host.name). Allow it on the Mac in Settings › Paired Devices, or update there.")
                .font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
        }
    }

    private func upToDateLine(_ status: HostUpdateStatus) -> String {
        guard let checked = status.lastChecked else { return "Up to date" }
        let age = DSFormat.compactAge(checked, now: .now)
        return age == "now" ? "Up to date · checked just now" : "Up to date · checked \(age) ago"
    }

    private func install(_ when: HostUpdateStatus.When) {
        Task { failure = await host.installUpdate(when) }
    }
}
