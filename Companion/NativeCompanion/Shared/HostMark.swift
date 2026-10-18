import NativeHostProtocol
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

/// The home screen's host switcher, in the header: the active host's mark and name, or every
/// host's marks for "All Hosts". Its menu picks the host and the Needs You filter.
struct HostChip: View {
    @Environment(CompanionStore.self) private var store
    @Binding var needsYouOnly: Bool

    var body: some View {
        @Bindable var store = store
        Menu {
            if store.hosts.count > 1 {
                Picker("Host", selection: $store.activeHostID) {
                    Label("All Hosts", systemImage: "square.stack").tag(HostID?.none)
                    ForEach(store.hosts) { host in
                        Label(host.name, systemImage: host.preferences.symbol).tag(Optional(host.id))
                    }
                }
            }
            Toggle("Needs You Only", isOn: $needsYouOnly)
        } label: {
            HStack(spacing: DS.Space.sm) {
                if let host = store.activeHost {
                    HostMark(preferences: host.preferences, size: CompanionMetrics.hostMarkSmall)
                    Text(host.name).lineLimit(1)
                } else {
                    HStack(spacing: -DS.Space.sm) {
                        ForEach(store.hosts.prefix(3)) { host in
                            HostMark(preferences: host.preferences, size: CompanionMetrics.hostMarkSmall)
                        }
                    }
                    Text("All Hosts")
                }
                Image(systemName: needsYouOnly ? "line.3.horizontal.decrease.circle.fill" : "chevron.down")
                    .font(.ds(CompanionMetrics.hostMarkTiny * 0.8, weight: .semibold))
                    .foregroundStyle(.dsTextSecondary)
            }
            .font(CompanionType.subheadline.weight(.medium))
            .foregroundStyle(.dsTextPrimary)
            .padding(.horizontal, DS.Space.xs)
        }
        .accessibilityLabel(store.activeHost.map { "Host: \($0.name)" } ?? "All Hosts")
        .accessibilityHint("Picks the host to show, and filters to what needs you.")
        .accessibilityIdentifier("hostChip")
    }
}

extension View {
    /// Tints a host's screens (toolbar buttons, links, switches) with the host's color: the quiet,
    /// always-on reminder of which host they belong to. A host left on `original` keeps the app's
    /// accent, so with one uncolored host nothing changes.
    func hostTint(_ preferences: HostPreferences?) -> some View {
        modifier(HostTint(themeID: preferences?.themeID))
    }
}

private struct HostTint: ViewModifier {
    let themeID: String?
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        // Always `.tint(_:)`, nil inheriting, so a color change never rebuilds the screen.
        content.tint(color)
    }

    private var color: Color? {
        guard let themeID, themeID != DSAccentPalette.original.id else { return nil }
        var host = environment
        host.dsAccentPalette = .named(themeID)
        return Color(Color.dsAccent.resolve(in: host))
    }
}
