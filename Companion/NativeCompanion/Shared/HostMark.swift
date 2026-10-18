import SwiftUI

/// A host's symbol in its chosen color: on every host row and task row, so it's clear which host
/// a task belongs to.
struct HostMark: View {
    let preferences: HostPreferences
    var size: CGFloat = CompanionMetrics.hostMark

    var body: some View {
        Image(systemName: preferences.symbol)
            .font(.ds(size * 0.5, weight: .medium))
            .foregroundStyle(.dsAccentText)
            .frame(width: size, height: size)
            .background(.dsAccentSubtle, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .dsAccentPalette(themeID: preferences.themeID)
            .accessibilityHidden(true)
    }
}

/// The one way a host's connection is shown: a dot and a word, with the reason under it when
/// something's wrong.
struct HostConnectionLine: View {
    let host: HostConnection

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Circle().fill(color).frame(width: DS.Space.md, height: DS.Space.md)
            Text(host.phase.title)
            if host.phase.isConnected, let lastSynced = host.lastSynced, Date.now.timeIntervalSince(lastSynced) > 120 {
                Text("· Updated \(DSFormat.compactAge(lastSynced, now: .now)) ago")
            }
        }
        .font(CompanionType.caption)
        .foregroundStyle(.dsTextSecondary)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch host.phase {
        case .connected: .dsSuccess
        case .connecting, .reconnecting: .dsWarning
        case .unreachable, .incompatible, .pairingEnded: .dsDanger
        }
    }
}
