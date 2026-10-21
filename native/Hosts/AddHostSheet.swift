import NativeHostProtocol
import NativeLink
import SwiftUI

/// Add Host: pair with another Mac over SSH or with the link its `pair` printed, see what the
/// pairing gives and choose before it happens, and say exactly what went wrong when it can't.
struct AddHostSheet: View {
    static let width: CGFloat = 460
    /// What to run on the other Mac by hand, for pairing without SSH from here.
    static let pairCommand =
        #""/Applications/Native.app/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host" pair --run-commands --install-updates"#

    @Bindable var model: AddHostModel
    let close: () -> Void
    @State private var copiedCommand = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            content
        }
        .padding(DS.Space.xxl)
        .frame(width: Self.width)
        .background(.dsBackground)
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .entering:
            entering
        case .reaching(let destination):
            if let page = model.approvalPage {
                approving(AddHostFailure.machine(destination), page: page)
            } else {
                working(
                    "Connecting to \(AddHostFailure.machine(destination))…",
                    detail:
                        "Signing in as \(destination) with your SSH keys, and asking Native there for a pairing link.")
            }
        case .confirming(let offer):
            confirming(offer)
        case .pairing(let offer):
            working("Pairing with \(offer.hostName)…", detail: model.progress ?? "Reaching it over the network.")
        case .paired(let name, let grants):
            paired(name, grants: grants)
        case .failed(let failure):
            failed(failure)
        }
    }

    // MARK: - Entering

    private var entering: some View {
        Group {
            header(
                "Add Host",
                detail:
                    "Run tasks on another Mac that stays on, like a Mac mini. They keep going while this Mac sleeps.")
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                TextField(
                    "SSH destination or pairing link", text: $model.input,
                    prompt: Text(verbatim: "me@mac-mini.local").foregroundStyle(.dsTextTertiary)
                )
                .settingsField(focus: $isFieldFocused)
                .onSubmit(model.submit)
                .accessibilityLabel("SSH destination or pairing link")
                // The returning field can take focus once it is in the window.
                .task { isFieldFocused = true }
                .onDisappear { isFieldFocused = false }
                Text(
                    "Native signs in with your SSH keys, starts a pairing link on that Mac and pairs with it. It never asks for a password."
                )
                .font(.dsCaption).foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                    Text("No SSH from here? Run this on that Mac and paste the link it prints.")
                        .font(.dsCaption).foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(copiedCommand ? "Copied" : "Copy Command") {
                        DSPasteboard.copy(Self.pairCommand)
                        copiedCommand = true
                    }
                    .buttonStyle(.ds(.ghost, size: .small))
                }
                codeBlock("Native Host pair --run-commands --install-updates")
            }
            footer {
                Button("Cancel", action: close).buttonStyle(.ds(.secondary, size: .large))
                Button("Continue", action: model.submit)
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Confirming

    private func confirming(_ offer: AddHostOffer) -> some View {
        Group {
            header("Pair with \(offer.hostName)?", detail: source(offer))
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("This Mac will be able to")
                    .font(.dsBody).foregroundStyle(.dsTextSecondary)
                Toggle("Run tasks on \(offer.hostName)", isOn: .constant(true))
                    .disabled(true)
                grant(
                    "Run commands and edit files in its projects", isOn: $model.requested.runCommands,
                    offered: offer.grants.runCommands, flag: "--run-commands",
                    note: "Git, diffs and terminals for tasks there need this.")
                grant(
                    "Install Native updates on it", isOn: $model.requested.manageHost,
                    offered: offer.grants.manageHost, flag: "--install-updates")
                grant(
                    "Turn its plugins on and off", isOn: $model.requested.managePlugins,
                    offered: offer.grants.managePlugins, flag: "--manage-plugins")
            }
            .addHostCheckboxes()
            .font(.dsBody)
            .foregroundStyle(.dsTextPrimary)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Reaches it at \(addresses(offer))")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(expiry(offer, now: context.date)).monospacedDigit()
                }
            }
            .font(.dsCaption).foregroundStyle(.dsTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            footer {
                Button("Cancel", action: close).buttonStyle(.ds(.secondary, size: .large))
                Button("Pair", action: model.pair)
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// One grant: a checkbox when the link offers it, else the option pair needs for it.
    private func grant(
        _ title: String, isOn: Binding<Bool>, offered: Bool, flag: String, note: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Toggle(title, isOn: offered ? isOn : .constant(false))
                .disabled(!offered)
            if let detail = offered ? note : "This link doesn't offer it. Run pair with \(flag) for one that does." {
                Text(detail)
                    .font(.dsCaption).foregroundStyle(.dsTextTertiary)
                    .padding(.leading, DS.Space.xl)
            }
        }
    }

    private func source(_ offer: AddHostOffer) -> String {
        let fingerprint = offer.invite.hostKey.fingerprint.chunked(by: 4)
        let build = offer.hostBuild.map { " It runs Native \($0.version)." } ?? ""
        guard let destination = offer.sshDestination else {
            return "From a pairing link.\(build) Its key is \(fingerprint)."
        }
        return "Reached over SSH as \(destination).\(build) Its key is \(fingerprint)."
    }

    private func addresses(_ offer: AddHostOffer) -> String {
        let reachable = offer.invite.addresses.filter { $0.kind != .relay && $0.kind != .unknown }
        return reachable.map(\.label).joined(separator: ", ")
    }

    private func expiry(_ offer: AddHostOffer, now: Date) -> String {
        guard let countdown = DSFormat.countdown(to: offer.invite.expiresAt, now: now) else {
            return "The link expired."
        }
        return "Single use. The link expires \(countdown)."
    }

    // MARK: - Working, done, failed

    private func working(_ title: String, detail: String) -> some View {
        Group {
            header(title)
            loading(detail)
            footer {
                Button("Cancel", action: close).buttonStyle(.ds(.secondary, size: .large))
            }
        }
    }

    /// The other Mac's SSH waits until the sign-in is approved in a browser; pairing carries on after.
    private func approving(_ machine: String, page: URL) -> some View {
        Group {
            header(
                "Approve the sign-in to \(machine)",
                detail:
                    "Its SSH asks you to confirm it's you in a browser before it lets Native in. Native carries on as soon as you approve."
            )
            codeBlock(page.absoluteString)
            loading("Waiting for approval…")
            footer {
                Button("Cancel", action: close).buttonStyle(.ds(.secondary, size: .large))
                Button("Open Approval Page") { openURL(page) }
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The one loader row: dots, then what's happening.
    private func loading(_ text: String) -> some View {
        HStack(spacing: DS.Space.md) {
            DotGridLoader(pattern: .settingUp)
            Text(text)
                .font(.dsBody).foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A command or address to read or copy, set apart from the prose around it.
    private func codeBlock(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dsMonoCaption).foregroundStyle(.dsTextPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control))
    }

    private func paired(_ name: String, grants: LinkGrants) -> some View {
        Group {
            HStack(alignment: .top, spacing: DS.Space.lg) {
                Image(systemName: "checkmark.circle")
                    .font(.dsTitle2)
                    .foregroundStyle(.dsSuccess)
                    .accessibilityHidden(true)
                header(
                    "\(name) is paired",
                    detail:
                        "Pick it in New Task to run tasks there. This Mac can \(grants.abilities) on it. Remove it any time in Settings › Hosts."
                )
            }
            footer {
                Button("Done", action: close)
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failed(_ failure: AddHostFailure) -> some View {
        Group {
            header("Add Host")
            ErrorState(
                failure.title, recovery: failure.recovery, suggestion: failure.suggestion(overSSH: model.wasOverSSH),
                details: failure.details,
                primary: nextStep(failure),
                secondary: model.canTryAgain ? .init("Edit", perform: model.edit) : nil)
            footer {
                Button("Close", action: close).buttonStyle(.ds(.secondary, size: .large))
            }
        }
    }

    /// Over SSH, trying again brings a new link; a pasted link needs a new one pasted.
    private func nextStep(_ failure: AddHostFailure) -> ErrorState.Action {
        if model.canTryAgain { return .init("Try Again", perform: model.retry) }
        if !model.wasOverSSH, failure.isWorthRetrying { return .init("Paste a New Link", perform: model.startOver) }
        return .init("Edit", perform: model.edit)
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
}

extension View {
    /// Checkboxes on the Mac; the platform's own toggles on iPad.
    fileprivate func addHostCheckboxes() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        self
        #endif
    }
}

extension String {
    /// "7QK2 M9XD 4R1P": groups of `size`, for reading a key's fingerprint aloud.
    fileprivate func chunked(by size: Int) -> String {
        stride(from: 0, to: count, by: size).map { offset in
            let start = index(startIndex, offsetBy: offset)
            return String(self[start..<(index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex)])
        }
        .joined(separator: " ")
    }
}

#if DEBUG
/// Fixtures for the previews.
private enum AddHostPreview {
    static let offer = AddHostOffer(
        invite: PairingInvite(
            hostID: RemoteHostID(), hostKey: LinkIdentity().publicKey, secret: Data(repeating: 1, count: 32),
            hostName: "Mac mini", expiresAt: .now.addingTimeInterval(272),
            addresses: [
                LinkAddress(kind: .lan, host: "192.168.1.20", port: 47_118),
                LinkAddress(kind: .tailnet, host: "mac-mini.tail1234.ts.net", port: 47_118),
                LinkAddress(kind: .bonjour, host: "Mac mini"),
            ],
            grants: AddHostModel.sshOffer),
        sshDestination: "me@mac-mini.local", hostBuild: PeerInfo(name: "Native Host", version: "1.4.0", build: "140"))

    static func model(_ phase: AddHostModel.Phase, approvalPage: URL? = nil) -> AddHostModel {
        AddHostModel(
            register: { _ in }, environment: { [:] }, input: "me@mac-mini.local", phase: phase,
            approvalPage: approvalPage)
    }
}

#Preview("Add Host") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.entering), close: {})
    }
}

#Preview("Confirm") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.confirming(AddHostPreview.offer)), close: {})
    }
}

#Preview("Approve") {
    DSPreviewPair {
        AddHostSheet(
            model: AddHostPreview.model(
                .reaching(destination: "me@mac-mini.local"),
                approvalPage: URL(string: "https://login.tailscale.com/a/l1b2c3")),
            close: {})
    }
}

#Preview("Pairing") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.pairing(AddHostPreview.offer)), close: {})
    }
}

#Preview("Paired") {
    DSPreviewPair {
        AddHostSheet(
            model: AddHostPreview.model(
                .paired(name: "Mac mini", grants: LinkGrants(manageHost: true, runCommands: true))),
            close: {})
    }
}

#Preview("Failed") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.failed(.sshSignIn(destination: "me@mac-mini.local"))), close: {})
    }
}
#endif
