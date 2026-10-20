import SwiftUI

/// Which device a session runs on, for sessions that don't run on this Mac: the device's glyph in
/// its color, and a mark only while it isn't online. Quiet by design, since most rows never need
/// it; the device's name and state are in its tooltip and VoiceOver label.
///
/// - `row`: the glyph alone, for a sidebar row's accessory slot.
/// - `header`: the glyph and the device's name in a session's header, plus the state in words
///   while it isn't online ("Mac mini · Offline").
struct HostDeviceBadge: View {
    enum Style {
        case row
        case header
    }

    let name: String
    let look: HostLook
    let availability: SessionDeviceOption.Availability
    var style = Style.row

    var body: some View {
        content
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .row:
            HStack(spacing: DS.Space.xxs) {
                HostGlyph(look: look, size: HostsMetrics.rowGlyph, isDimmed: !availability.isOnline)
                if !availability.isOnline {
                    HostAvailabilityMark(availability: availability)
                }
            }
            .fixedSize()
        case .header:
            HStack(spacing: DS.Space.sm) {
                HostGlyph(look: look, size: HostsMetrics.calloutGlyph, isDimmed: !availability.isOnline)
                Text(name)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                if !availability.isOnline {
                    Text("·").foregroundStyle(.dsTextQuaternary)
                    HostAvailabilityMark(availability: availability)
                    Text(availability.statusTitle)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.dsCallout)
        }
    }

    /// "Runs on Mac mini", then what's wrong when something is.
    private var help: String {
        switch availability {
        case .online: "Runs on \(name)"
        case .connecting: "Runs on \(name), which Native is connecting to"
        case .offline(let reason): "Runs on \(name), which is offline. \(reason)"
        }
    }

    private var spoken: String {
        switch availability {
        case .online: "On \(name)"
        case .connecting: "On \(name), connecting"
        case .offline(let reason): "On \(name), offline. \(reason)"
        }
    }
}

#Preview("Device badges") {
    let mini = HostLook(symbol: .mini, tint: .cobalt)
    let server = HostLook(symbol: .server, tint: .fern)
    let offline = SessionDeviceOption.Availability.offline(reason: "Not reachable. The connection timed out.")
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            TaskRow(
                title: "Migrate the billing webhooks", status: .working, date: .now,
                accessory: HostDeviceBadge(name: "Mac mini", look: mini, availability: .online), action: {})
            TaskRow(
                title: "Nightly dependency bumps", status: .idle, date: .now.addingTimeInterval(-7200),
                accessory: HostDeviceBadge(name: "Mac mini", look: mini, availability: .connecting), action: {})
            TaskRow(
                title: "Profile the indexer", status: .needsInput, date: .now.addingTimeInterval(-600),
                accessory: HostDeviceBadge(name: "build-box", look: server, availability: offline), action: {})
            SeparatorLine()
            HostDeviceBadge(name: "Mac mini", look: mini, availability: .online, style: .header)
            HostDeviceBadge(name: "Mac mini", look: mini, availability: .connecting, style: .header)
            HostDeviceBadge(name: "build-box", look: server, availability: offline, style: .header)
        }
        .frame(width: DS.Size.sidebarWidth)
    }
}
