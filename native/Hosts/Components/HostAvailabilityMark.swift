import SwiftUI

/// Whether a device can take work now, as one small mark: a green dot while it's online, the
/// waiting loader while it connects, an amber dot while it's offline. The same marks the status
/// bar's host item uses, so a host's state reads the same everywhere.
struct HostAvailabilityMark: View {
    let availability: SessionDeviceOption.Availability

    var body: some View {
        switch availability {
        case .online:
            StatusDot(color: .dsSuccess)
        case .connecting:
            DotGridLoader(pattern: .waiting)
                .frame(width: HostsMetrics.loader, height: HostsMetrics.loader)
                .accessibilityHidden(true)
        case .offline:
            StatusDot(color: .dsWarning)
        }
    }
}

extension SessionDeviceOption.Availability {
    /// One or two words for the state: "Online", "Connecting…", "Offline".
    var statusTitle: String {
        switch self {
        case .online: "Online"
        case .connecting: "Connecting…"
        case .offline: "Offline"
        }
    }

    var isOnline: Bool {
        self == .online
    }
}

#Preview("Availability marks") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(
                [SessionDeviceOption.Availability.online, .connecting, .offline(reason: "Not reachable.")], id: \.self
            ) { availability in
                HStack(spacing: DS.Space.sm) {
                    HostAvailabilityMark(availability: availability)
                    Text(availability.statusTitle)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
        }
    }
}
