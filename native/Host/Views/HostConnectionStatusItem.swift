import NativeHostClient
import SwiftUI

/// The status bar's background-host item. It only shows while something is off: reconnecting after
/// the connection dropped, the host out of reach, or for a while after the host restarted. Click for
/// what happened and what Native is doing about it. A host that stays out of reach also gets a
/// notice above the detail column (`HostNotices`), since the status bar can be hidden.
struct HostConnectionStatusItem: StatusBarItem {
    let host: DurableHost

    let id = "background-host"
    let title = "Background Host"
    let placement = StatusBarPlacement.leading
    let order = 60

    var content: some View {
        HostConnectionSegment(host: host)
    }
}

private struct HostConnectionSegment: View {
    let host: DurableHost

    /// What the segment says right now, or nil when all is well.
    private enum Condition: Equatable {
        case reconnecting(String)
        case unreachable(String)
        case restarted(HostRestart)
    }

    private var condition: Condition? {
        guard host.placement.usesHost else { return nil }
        switch host.connection {
        case .reconnecting(_, let reason): return .reconnecting(reason)
        case .unreachable(let reason): return .unreachable(reason)
        default: return host.restart.map(Condition.restarted)
        }
    }

    var body: some View {
        if let condition {
            StatusBarSegment(
                help: help(condition), accessibilityLabel: "Background host", accessibilityValue: label(condition)
            ) {
                HStack(spacing: DS.Space.sm) {
                    switch condition {
                    case .reconnecting:
                        DotGridLoader(pattern: .waiting)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    case .unreachable:
                        StatusBarGlyph("bolt.horizontal.circle")
                    case .restarted:
                        StatusBarGlyph("arrow.clockwise")
                    }
                    Text(label(condition))
                    if case .unreachable = condition {
                        StatusDot(color: .dsWarning)
                    }
                }
            } details: {
                details(condition)
            }
        }
    }

    private func label(_ condition: Condition) -> String {
        switch condition {
        case .reconnecting: "Reconnecting…"
        case .unreachable: "Host not responding"
        case .restarted: "Host restarted"
        }
    }

    private func help(_ condition: Condition) -> String {
        switch condition {
        case .reconnecting: "Native is reconnecting to its background host. Your tasks keep running there."
        case .unreachable: "Native's background host isn't answering. Native keeps trying."
        case .restarted(let restart): restart.sentence
        }
    }

    private func details(_ condition: Condition) -> some View {
        PopoverPanel(title: "Background Host", systemImage: "moon.zzz") {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                switch condition {
                case .reconnecting(let reason):
                    paragraph(
                        "Native lost its connection to the background host and is reconnecting. Your tasks keep running there, and messages you send go out once it's back.",
                        footnote: reason)
                case .unreachable(let reason):
                    paragraph(
                        "Native's background host isn't answering. Your tasks keep their place, and Native keeps trying.",
                        footnote: reason)
                    Button("Restart Host") { Task { await host.startHostAgain() } }
                        .buttonStyle(.ds(.secondary))
                case .restarted(let restart):
                    paragraph(
                        restart.sentence,
                        footnote: restart.resumed > 0 ? "Each task says so in its transcript, where it happened." : nil)
                    Button("Dismiss", action: host.dismissRestart)
                        .buttonStyle(.ds(.secondary))
                }
            }
            .padding(DS.Space.lg)
        }
    }

    private func paragraph(_ text: String, footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(text)
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
