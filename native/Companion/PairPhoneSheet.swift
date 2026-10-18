import NativeLink
import SwiftUI

/// The Pair iPhone sheet: a QR code and a typed code that expire in five minutes and refresh on
/// their own, then the device by name with the verification code both screens show, before this
/// Mac trusts it (`docs/companion.md`, "Pairing").
struct PairPhoneSheet: View {
    static let qrSize: CGFloat = 196
    static let width: CGFloat = 420

    let model: PairedDevicesModel
    let close: () -> Void

    @State private var grants = LinkGrants.standard
    @State private var grantsFor: VerificationCode?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            content
        }
        .padding(DS.Space.xxl)
        .frame(width: Self.width)
        .background(.dsBackground)
    }

    @ViewBuilder
    private var content: some View {
        if let pairing = model.status?.pairing {
            switch pairing.phase {
            case .confirming:
                if let request = pairing.request { confirm(request) }
            case .paired:
                paired(pairing)
            case .rejected:
                outcome(
                    "Not paired", systemImage: "xmark.circle",
                    message: "The device wasn't trusted. Make a new code to pair another one.")
            case .expired:
                outcome(
                    "Nobody confirmed in time", systemImage: "clock",
                    message: "The device stopped waiting. Make a new code and try again.")
            case .tooManyAttempts:
                outcome(
                    "Too many wrong codes", systemImage: "exclamationmark.triangle",
                    message: "Three codes didn't match, so this one is closed. Make a new code on this Mac.")
            case .open, .unknown:
                invite(pairing)
            }
        } else if let reason = model.unavailableReason {
            header("Pair iPhone")
            NoticeBanner(
                tone: .warning, title: "Native's background host isn't reachable", detail: reason)
            footer { Button("Close", action: close).buttonStyle(.ds(.secondary, size: .large)) }
        } else {
            header("Pair iPhone")
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .settingUp)
                Text("Making a code…").font(.dsBody).foregroundStyle(.dsTextSecondary)
            }
            footer { Button("Cancel", action: close).buttonStyle(.ds(.secondary, size: .large)) }
        }
    }

    private func invite(_ pairing: LinkPairingStatus) -> some View {
        Group {
            header("Pair iPhone", detail: "In Native on your iPhone, tap Pair with Your Mac and scan this code.")
            HStack {
                Spacer()
                PairingQRCodeImage(text: pairing.invite.url.absoluteString, size: Self.qrSize)
                    .padding(DS.Space.lg)
                    // The code's quiet zone: white in both appearances, since inverted codes scan badly.
                    .background(.white, in: .rect(cornerRadius: DS.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsBorder))
                Spacer()
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("No camera? Enter this code instead")
                    .font(.dsBody).foregroundStyle(.dsTextSecondary)
                Text(pairing.displayCode)
                    .font(.ds(22, weight: .medium, design: .mono))
                    .tracking(4)
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code \(pairing.displayCode)")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(expiry(pairing, now: context.date))
                        .font(.dsCaption).foregroundStyle(.dsTextTertiary)
                        .monospacedDigit()
                }
                if pairing.failedAttempts > 0 {
                    Text(
                        "\(pairing.failedAttempts) wrong code\(pairing.failedAttempts == 1 ? "" : "s") so far. Three closes this code."
                    )
                    .font(.dsCaption).foregroundStyle(.dsWarning)
                }
            }
            footer {
                Button("Cancel", action: close).buttonStyle(.ds(.secondary, size: .large))
            }
        }
    }

    private func confirm(_ request: LinkPairingRequest) -> some View {
        Group {
            header(
                "Pair “\(request.device.name)”?",
                detail:
                    "\(request.device.model) · \(request.device.system). It will see this Mac's tasks, and can answer agents and send messages."
            )
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Check that the device shows")
                    .font(.dsBody).foregroundStyle(.dsTextSecondary)
                Text(request.verification.description)
                    .font(.ds(28, weight: .medium, design: .mono))
                    .tracking(3)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityLabel("Verification code \(request.verification.description)")
                if request.usedCode {
                    Text("It paired with the typed code, so only pair if these numbers match.")
                        .font(.dsCaption).foregroundStyle(.dsTextTertiary)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Toggle("Allow installing updates for this Mac's Native", isOn: $grants.manageHost)
                Toggle("Allow turning plugins on and off", isOn: $grants.managePlugins)
            }
            .toggleStyle(.checkbox)
            .font(.dsBody)
            .foregroundStyle(.dsTextPrimary)
            footer {
                Button("Don't Pair") { model.decide(accept: false, grants: .standard) }
                    .buttonStyle(.ds(.secondary, size: .large))
                Button("Pair") { model.decide(accept: true, grants: grants) }
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { resetGrants(for: request) }
        .onChange(of: request.verification) { resetGrants(for: request) }
    }

    private func paired(_ pairing: LinkPairingStatus) -> some View {
        let name =
            model.status?.devices.first { $0.id == pairing.pairedDeviceID }?.device.name ?? "Your device"
        return outcome(
            "\(name) is paired", systemImage: "checkmark.circle",
            message: "It can follow this Mac's tasks now. Remove it any time in Settings › Paired Devices.",
            isSuccess: true)
    }

    private func outcome(_ title: String, systemImage: String, message: String, isSuccess: Bool = false) -> some View {
        Group {
            HStack(alignment: .top, spacing: DS.Space.lg) {
                Image(systemName: systemImage)
                    .font(.dsTitle2)
                    .foregroundStyle(isSuccess ? .dsSuccess : .dsTextSecondary)
                    // The heading says it; the symbol's own label ("Selected") would mislead.
                    .accessibilityHidden(true)
                header(title, detail: message)
            }
            footer {
                if !isSuccess {
                    Button("New Code") { model.newCode() }
                        .buttonStyle(.ds(.secondary, size: .large))
                }
                Button("Done", action: close)
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func header(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(.dsTitle3)
                .foregroundStyle(.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func footer(@ViewBuilder _ buttons: () -> some View) -> some View {
        HStack(spacing: DS.Space.md) {
            Spacer()
            buttons()
        }
    }

    private func expiry(_ pairing: LinkPairingStatus, now: Date) -> String {
        guard let countdown = DSFormat.countdown(to: pairing.expiresAt, now: now) else { return "Making a new code…" }
        return "Single use. A new code replaces it \(countdown)."
    }

    private func resetGrants(for request: LinkPairingRequest) {
        guard grantsFor != request.verification else { return }
        grantsFor = request.verification
        grants = .suggested(usedCode: request.usedCode)
    }
}
