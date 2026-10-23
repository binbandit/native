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
    var answersShortcut = false
    var askShortcut: KeyboardShortcut? = KeyboardShortcut("y", modifiers: .command)
    var unavailable: String?
    var hostName: String?
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
                        if status.needsAttention, unavailable == nil, let attentionSince {
                            DSMinuteTimeline { now in
                                Text(DSFormat.compactAge(attentionSince, now: now))
                                    .font(DS.Sidebar.clockFont)
                                    .monospacedDigit()
                                    .foregroundStyle(.dsAttention)
                            }
                            .fixedSize()
                        }
                        if let hostName {
                            Image(systemName: "macmini")
                                .font(.dsBody)
                                .foregroundStyle(.dsTextTertiary)
                                .help(hostName)
                        }
                    }
                    .frame(height: DS.Sidebar.titleHeight)
                    if let sentence = unavailable ?? ask {
                        HStack(alignment: .bottom, spacing: DS.Space.md) {
                            DSInlineCodeText(sentence, codeFont: DS.Sidebar.askCodeFont, codeColor: .dsTextPrimary)
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
                unavailable ?? status.label, isUnread ? "Unread" : nil, ask,
                answersShortcut ? "Oldest ask" : nil,
            ].compactMap(\.self).joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var signal: some View {
        TaskSignal(status: status, isUnread: isUnread, attentionSince: attentionSince, unavailable: unavailable)
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
#endif
