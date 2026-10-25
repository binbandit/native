import SwiftUI

/// Titles at rest; an ask speaks in up to two lines and keeps its clock beside the title.
/// The shortcut is informational and belongs only to the request the window actually answers.
public struct AllInViewTaskRow: View {
    let title: String
    let status: TaskStatus
    var isSelected = false
    var isPeeking = false
    var isUnread = false
    var ask: String?
    var attentionSince: Date?
    var showsAttentionClock = true
    var answersShortcut = false
    var askShortcut: KeyboardShortcut? = KeyboardShortcut("y", modifiers: .command)
    var unavailable: String?
    var hostName: String?
    var projectName: String?
    var date: Date?
    var changes: (added: Int, removed: Int)?
    var agentName: String?
    var branchName: String?
    var peek: (() -> Void)?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.taskSignalReducedMotion) private var stillSignals
    @State private var isHovered = false

    private var reduceMotion: Bool { systemReduceMotion || stillSignals }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                signal
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                VStack(alignment: .leading, spacing: DS.Sidebar.askGap) {
                    HStack(spacing: DS.Space.md) {
                        DSInlineCodeText(title)
                            .font(isUnread ? .dsCalloutSemibold : .dsCalloutBook)
                            .tracking(DS.Sidebar.titleTracking)
                            .foregroundStyle(emphasizesTitle ? .dsTextPrimary : .dsTextSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showsAttentionClock, status.needsAttention, unavailable == nil, let attentionSince {
                            TaskAttentionClock(since: attentionSince)
                        }
                        if let hostName {
                            Image(systemName: "macmini")
                                .font(.dsBody)
                                .foregroundStyle(.dsTextTertiary)
                                .help(hostName)
                        }
                        if let changes, changes.added > 0 || changes.removed > 0 {
                            DiffStatLabel(added: changes.added, removed: changes.removed).fixedSize()
                        }
                        if !status.needsAttention, let date {
                            DSMinuteTimeline { now in
                                Text(DSFormat.compactAge(date, now: now))
                                    .font(DS.Sidebar.ageFont)
                                    .foregroundStyle(.dsTextTertiary)
                            }.fixedSize()
                        }
                    }
                    .frame(height: DS.Sidebar.titleHeight)
                    if let sentence = unavailable ?? ask {
                        HStack(alignment: .bottom, spacing: DS.Space.md) {
                            askText(sentence)
                                .font(.dsBody)
                                .foregroundStyle(unavailable == nil ? .dsTextSecondary : .dsTextTertiary)
                                .lineSpacing(DS.Sidebar.askLineSpacing)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: DS.Sidebar.askLineHeight, alignment: .bottomLeading)
                            if answersShortcut, unavailable == nil, let askShortcut {
                                Kbd(askShortcut, compact: true)
                                    .padding(.bottom, DS.Sidebar.keycapBottom)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if agentName != nil || branchName != nil {
                        facts
                    }
                }
            }
            .padding(.leading, DS.Sidebar.leading)
            .padding(.trailing, DS.Sidebar.trailing)
            .padding(.vertical, DS.Sidebar.rowVertical)
            .frame(minHeight: max(DS.Sidebar.rowHeight, DS.Size.minimumHitTarget))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected || isPeeking ? .dsSelected : isHovered ? .dsHover : .clear)
                .overlay {
                    if isPeeking {
                        RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous).strokeBorder(.dsBorder)
                    }
                }
        }
        .overlay(alignment: .topLeading) {
            if let peek {
                Button(action: peek) { Color.clear }
                    .buttonStyle(.plain)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                    .contentShape(.rect)
                    .dsHitTarget(DS.Size.rowLeading)
                    .padding(.leading, DS.Sidebar.leading)
                    .padding(.top, DS.Sidebar.rowVertical)
                    .help("Peek")
                    .accessibilityLabel("Peek at \(DSInlineCode.plain(title))")
            }
        }
        .trackHover($isHovered)
        .animation(reduceMotion ? nil : ask == nil ? .dsSidebarAnswer : .dsSidebarAsk, value: ask)
        .accessibilityLabel(DSInlineCode.plain(title))
        .accessibilityValue(
            [
                projectName, unavailable ?? status.label, isUnread ? "Unread" : nil, ask.map(DSInlineCode.plain),
                agentName, branchName,
                changes.map { DSFormat.spokenDiffStat(added: $0.added, removed: $0.removed) },
                answersShortcut ? "Oldest ask" : nil,
            ].compactMap(\.self).joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The agent keeps its name; a long branch gives up its middle, so its prefix and its end
    /// (where branches differ) both stay readable.
    private var facts: some View {
        HStack(spacing: 0) {
            if let agentName {
                Text(agentName).fixedSize()
                if branchName != nil { Text(" · ").fixedSize() }
            }
            if let branchName {
                Text(branchName).truncationMode(.middle)
            }
        }
        .font(DS.Sidebar.factFont)
        .foregroundStyle(.dsTextTertiary)
        .lineLimit(1)
        .help([agentName, branchName].compactMap(\.self).joined(separator: " · "))
    }

    private var signal: some View {
        TaskSignal(status: status, isUnread: isUnread, attentionSince: attentionSince, unavailable: unavailable)
    }

    private func askText(_ sentence: String) -> Text {
        var text = AttributedString()
        if let projectName {
            var project = AttributedString("\(projectName)  ")
            project.font = DS.Sidebar.attentionProjectFont
            project.foregroundColor = .dsTextTertiary
            text += project
        }
        text += DSInlineCode.attributed(sentence, codeFont: DS.Sidebar.askCodeFont, codeColor: .dsTextPrimary)
        return Text(text)
    }

    private var emphasizesTitle: Bool {
        isSelected || isPeeking || isUnread || status.needsAttention || status == .failed
    }
}

#if DEBUG
#Preview("All in view rows - Rest, asks, failure, offline, long text") {
    DSPreviewPair {
        VStack(spacing: 0) {
            AllInViewTaskRow(title: "Queue follow-ups while a turn runs", status: .working) {}
            AllInViewTaskRow(
                title: "Fix flaky `PermissionRequestTests`", status: .needsPermission,
                ask: "Allow `swift test`?", attentionSince: .now.addingTimeInterval(-720), answersShortcut: true
            ) {}
            AllInViewTaskRow(
                title: "`kt pr` reads the PR template", status: .needsInput,
                ask: "Use the repo's PR template, or keep the built-in body?", attentionSince: .now
            ) {}
            AllInViewTaskRow(title: "Wrap diff lines at word boundaries", status: .done, isSelected: true) {}
            AllInViewTaskRow(
                title: "Squash the release notes on main", status: .needsPermission, isPeeking: true,
                ask: "Allow `git push`?", attentionSince: .now.addingTimeInterval(-240), peek: {}
            ) {}
            AllInViewTaskRow(title: "Task titles from the first prompt", status: .done, isUnread: true) {}
            AllInViewTaskRow(
                title: "Landing page hero", status: .failed,
                ask: "The provider is still overloaded. Try again or switch models."
            ) {}
            AllInViewTaskRow(
                title: "Retry uploads when the network drops", status: .working,
                unavailable: "build-mac is offline. Reconnect to continue.", hostName: "build-mac"
            ) {}
            AllInViewTaskRow(
                title: "A very long task title that must truncate within the row", status: .needsPlanReview,
                ask:
                    "Review the migration plan covering the authentication routes and every dependent package before proceeding.",
                attentionSince: .now, answersShortcut: true
            ) {}
        }
        .frame(width: DS.Size.sidebarWidth - DS.Sidebar.inset * 2)
    }
}
#Preview("All in view - Optional facts and folded Home ask") {
    DSPreviewPair {
        VStack(spacing: 0) {
            AllInViewTaskRow(
                title: "Wrap diff lines at word boundaries", status: .done, isSelected: true,
                date: .now.addingTimeInterval(-1080), changes: (24, 6), agentName: "Codex",
                branchName: "fix/diff-word-wrap"
            ) {}
            AllInViewTaskRow(
                title: "Fix flaky `PermissionRequestTests`", status: .needsPermission,
                attentionSince: .now.addingTimeInterval(-720), showsAttentionClock: false
            ) {}
            AllInViewTaskRow(
                title: "A task with a long branch and agent name", status: .working, agentName: "Claude Code",
                branchName: "feature/authentication-migration-and-dependent-packages"
            ) {}
        }.frame(width: DS.Size.sidebarWidth - DS.Sidebar.inset * 2)
    }
}
#endif
