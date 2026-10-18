import NativeLink
import SwiftUI

/// Where a pairing is: connecting, waiting for the Mac (both screens show the same digits),
/// paired (name it and pick its color), or failed with the reason and the pairing log.
struct PairingProgressView: View {
    let flow: PairingFlow
    let retry: () -> Void
    let done: () -> Void

    @Environment(CompanionStore.self) private var store
    @State private var label = ""
    @State private var themeID = CompanionAppIcon.original.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                switch flow.step {
                case .idle:
                    EmptyView()
                case .connecting(let name):
                    status(
                        "Connecting to \(name)…",
                        detail: "Checking that it's the Mac you scanned, then proving the code.",
                        loader: .settingUp)
                case .confirming(let name, let code):
                    status(
                        "Confirm on \(name)", detail: "Click Pair on the Mac if it shows these numbers too.",
                        loader: .waiting)
                    Text(code.description)
                        .font(CompanionType.code)
                        .tracking(4)
                        .foregroundStyle(.dsTextPrimary)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("verificationCode")
                case .paired(let host):
                    paired(host)
                case .failed(let message):
                    ErrorState(
                        "Couldn't pair", suggestion: message, details: logText,
                        primary: .init("Try Again", perform: retry), layout: .pane)
                }
            }
            .padding(DS.Space.xxl)
            .frame(maxWidth: CompanionMetrics.readableWidth)
        }
    }

    private func status(_ title: String, detail: String, loader: DotGridLoader.Pattern) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DotGridLoader(pattern: loader)
                .frame(width: CompanionMetrics.hostMark, height: CompanionMetrics.hostMark)
            Text(title).font(CompanionType.title).foregroundStyle(.dsTextPrimary)
            Text(detail).font(CompanionType.body).foregroundStyle(.dsTextSecondary)
        }
    }

    private func paired(_ host: PairedHost) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Label("Paired with \(host.machineName)", systemImage: "checkmark.circle.fill")
                .font(CompanionType.title)
                .foregroundStyle(.dsTextPrimary)
            Text("Name it so you can tell it apart on this phone. Only this phone sees the name.")
                .font(CompanionType.body).foregroundStyle(.dsTextSecondary)
            TextField(host.machineName, text: $label)
                .font(CompanionType.body)
                .padding(DS.Space.lg)
                .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
                .accessibilityIdentifier("hostName")
            HostThemePicker(themeID: $themeID)
            Button {
                if let connection = store.host(host.hostID) {
                    var preferences = connection.preferences
                    preferences.label = label.isEmpty ? nil : label
                    preferences.themeID = themeID
                    connection.preferences = preferences
                }
                done()
            } label: {
                Text("Done").font(CompanionType.bodyMedium).frame(maxWidth: .infinity, minHeight: CompanionMetrics.pill)
            }
            .buttonStyle(.ds(.primary, size: .large))
            .accessibilityIdentifier("pairingDone")
        }
        // Pairing a host again keeps what this phone already calls it.
        .onAppear {
            guard let preferences = store.host(host.hostID)?.preferences else { return }
            label = preferences.label ?? ""
            themeID = preferences.themeID
        }
    }

    private var logText: String {
        flow.log.map { "\($0.date.formatted(date: .omitted, time: .standard))  \($0.message)" }.joined(separator: "\n")
    }
}

/// The accent palettes as swatches, for naming a host's color.
struct HostThemePicker: View {
    @Binding var themeID: String

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            ForEach(CompanionAppIcon.allCases) { theme in
                Button {
                    themeID = theme.rawValue
                } label: {
                    Circle()
                        .fill(.dsAccent)
                        .frame(width: CompanionMetrics.hostMark, height: CompanionMetrics.hostMark)
                        .overlay {
                            if themeID == theme.rawValue {
                                Circle().strokeBorder(.dsTextPrimary, lineWidth: DS.Space.xxs)
                            }
                        }
                        .dsAccentPalette(themeID: theme.rawValue)
                }
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(themeID == theme.rawValue ? .isSelected : [])
            }
        }
    }
}
