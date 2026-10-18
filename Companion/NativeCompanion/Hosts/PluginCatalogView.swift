import ACP
import NativeHostProtocol
import NativeLink
import SwiftUI

/// A host's plugins. They run on the host; this phone sees them and, if the Mac allowed it when
/// pairing (or later in Settings › Paired Devices), turns them on and off for everyone on the host.
/// Appearance-only plugins installed on the phone itself will join this list as a second source.
struct PluginCatalogView: View {
    let host: HostConnection

    @State private var failure: String?

    var body: some View {
        List {
            if let failure {
                Text(failure).font(CompanionType.caption).foregroundStyle(.dsDanger)
            }
            Section {
                ForEach(host.plugins) { plugin in
                    row(plugin)
                }
            } footer: {
                Text(
                    host.host.grants.managePlugins
                        ? "Changes apply on \(host.name) for everyone using it."
                        : "Turning plugins on and off from this iPhone needs permission on the Mac, in Settings › Paired Devices."
                )
            }
        }
        .overlay {
            if host.plugins.isEmpty {
                EmptyStateView(
                    "No plugins on \(host.name)", systemImage: "puzzlepiece.extension",
                    message: "Plugins added on the Mac show here.")
            }
        }
        .font(CompanionType.body)
        .scrollContentBackground(.hidden)
        .background(.dsBackground)
        .navigationTitle("Plugins")
    }

    @ViewBuilder
    private func row(_ plugin: HostPlugin) -> some View {
        let label = VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(plugin.name).foregroundStyle(.dsTextPrimary)
            Text(
                [plugin.version, plugin.manifest["description"]?.stringValue].compactMap { $0 }.joined(separator: " · ")
            )
            .font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
            .lineLimit(2)
        }
        if host.host.grants.managePlugins {
            Toggle(
                isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { isOn in
                        Task { failure = await host.setPlugin(plugin.id, enabled: isOn) }
                    })
            ) { label }
        } else {
            LabeledContent {
                Text(plugin.isEnabled ? "On" : "Off").foregroundStyle(.dsTextSecondary)
            } label: {
                label
            }
        }
    }
}
