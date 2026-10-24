import NativeLink
import NativePolicy
import SwiftUI
import UIKit

/// Adding a host: scan the Mac's QR code, or pick a Mac Bonjour found and type its code, or paste
/// the link. A pairing link that opened the app goes straight to pairing.
struct AddHostView: View {
    @Environment(CompanionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var flow = PairingFlow()
    @State private var isScanning = false
    @State private var codeHost: DiscoveredHost?
    @State private var typedCode = ""
    @State private var scanProblem: String?

    var body: some View {
        NavigationStack {
            Group {
                if !Self.policy.companionEnabled {
                    EmptyStateView(
                        "Pairing is turned off", systemImage: "building.2",
                        message:
                            "The organization that manages this iPhone turned off pairing with hosts. Hosts already paired keep working."
                    )
                } else if flow.step == .idle {
                    chooser
                } else {
                    PairingProgressView(flow: flow, retry: { flow.reset() }, done: { dismiss() })
                }
            }
            .navigationTitle("Add Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        flow.cancel()
                        dismiss()
                    }
                }
            }
            .background(.dsBackground)
        }
        .task {
            if let invite = store.pendingInvite {
                store.pendingInvite = nil
                flow.pair(invite: invite, discovered: store.discovered, store: store)
            }
        }
    }

    /// The organization's managed configuration for this iPhone (`policy.companion.enabled`).
    private static var policy: NativePolicy { PolicyLoader.load(from: NativePolicy.platformSource()) }

    private var chooser: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    Text("On your Mac, open Native ▸ Settings ▸ Paired Devices and click Pair iPhone.")
                        .font(CompanionType.body)
                        .foregroundStyle(.dsTextPrimary)
                    if isScanning {
                        QRScannerView { payload in
                            guard let invite = try? PairingInvite(url: payload) else {
                                scanProblem = "That QR code isn't a Native pairing code."
                                return
                            }
                            isScanning = false
                            flow.pair(invite: invite, discovered: store.discovered, store: store)
                        }
                        .frame(
                            height: verticalSizeClass == .compact
                                ? CompanionMetrics.scannerCompactHeight : CompanionMetrics.scannerHeight
                        )
                        .clipShape(.rect(cornerRadius: DS.Radius.panel))
                    }
                    Button {
                        isScanning.toggle()
                    } label: {
                        Label(isScanning ? "Stop Scanning" : "Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(CompanionType.bodyMedium)
                            .frame(maxWidth: .infinity, minHeight: CompanionMetrics.pill)
                    }
                    .buttonStyle(.ds(.primary, size: .large))
                    .disabled(!QRScannerView.isAvailable)
                    if !QRScannerView.isAvailable {
                        Text("The camera can't scan on this device. Type the code or paste the link instead.")
                            .font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
                    }
                    if let scanProblem {
                        Text(scanProblem).font(CompanionType.caption).foregroundStyle(.dsWarning)
                    }
                }
                .listRowBackground(Color.clear)
            }
            Section {
                if store.discovered.isEmpty {
                    HStack(spacing: DS.Space.md) {
                        DotGridLoader(pattern: .waiting)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                        Text("Looking for Macs running Native on this network…")
                            .font(CompanionType.subheadline).foregroundStyle(.dsTextSecondary)
                    }
                } else {
                    ForEach(store.discovered) { host in
                        discoveredRow(host)
                    }
                }
            } header: {
                Text("Enter a code instead")
            } footer: {
                Text("The Mac shows a six-character code under its QR code.")
            }
            Section {
                Button {
                    pasteLink()
                } label: {
                    Label("Paste Pairing Link", systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("pastePairingLink")
            }
        }
        .scrollContentBackground(.hidden)
        .font(CompanionType.body)
        .alert(
            "Enter the code from \(codeHost?.name ?? "your Mac")",
            isPresented: Binding(get: { codeHost != nil }, set: { if !$0 { codeHost = nil } })
        ) {
            TextField("K7Q 4MX", text: $typedCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Pair") { pairWithCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's under the QR code on the Mac.")
        }
    }

    private func discoveredRow(_ host: DiscoveredHost) -> some View {
        let paired = store.hosts.first { $0.host.hostKey.fingerprint == host.fingerprint }
        return Button {
            typedCode = ""
            codeHost = host
        } label: {
            HStack {
                Image(systemName: "desktopcomputer").foregroundStyle(.dsTextSecondary)
                VStack(alignment: .leading) {
                    Text(host.name).foregroundStyle(.dsTextPrimary)
                    Text(paired.map { "Paired as \($0.name)" } ?? "On this network")
                        .font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.dsTextTertiary)
            }
        }
    }

    private func pairWithCode() {
        guard let host = codeHost else { return }
        guard let code = PairingCode(typed: typedCode) else {
            store.problem = "Codes are six letters and numbers, like K7Q 4MX."
            return
        }
        flow.pair(code: code, with: host, store: store)
    }

    private func pasteLink() {
        guard let text = UIPasteboard.general.string, let invite = try? PairingInvite(url: text) else {
            store.problem =
                "The clipboard doesn't hold a Native pairing link. Copy it from the Mac's Pair iPhone sheet."
            return
        }
        flow.pair(invite: invite, discovered: store.discovered, store: store)
    }
}

#if DEBUG
#Preview("Add host - Compact height") {
    DSPreviewPair {
        AddHostView()
            .environment(CompanionStore(previewHosts: []))
            .environment(\.verticalSizeClass, .compact)
            .frame(width: 760, height: 390)
    }
}
#endif
