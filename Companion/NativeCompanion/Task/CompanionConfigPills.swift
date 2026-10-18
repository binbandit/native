import ACP
import NativeHostProtocol
import SwiftUI

/// The agent's own choices for this task (model, effort, mode) as a row of pills, like the Mac's
/// composer. Only what the agent offers shows; a change applies from its next turn.
struct CompanionConfigPills: View {
    let host: HostConnection
    let sessionID: HostSessionID

    @State private var failure: String?

    var body: some View {
        let options = (host.mirrors[sessionID]?.state.configOptions ?? []).compactMap {
            option -> (ConfigOption, String, [ConfigOption.SelectOption])? in
            guard case .select(let current, let choices) = option.kind, choices.count > 1 else { return nil }
            return (option, current, choices)
        }
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.sm) {
                        ForEach(options, id: \.0.id) { option, current, choices in
                            Menu {
                                Picker(
                                    option.name, selection: Binding(get: { current }, set: { choose($0, for: option) })
                                ) {
                                    ForEach(choices) { choice in
                                        Text(choice.name).tag(choice.value)
                                    }
                                }
                            } label: {
                                Label(
                                    choices.first { $0.value == current }?.name ?? current, systemImage: symbol(option)
                                )
                                .font(CompanionType.caption)
                                .padding(.horizontal, DS.Space.md)
                                .frame(minHeight: DS.Size.composerPill)
                                .background(.dsSurface, in: .capsule)
                            }
                            .accessibilityIdentifier("config-\(option.category ?? option.id)")
                        }
                    }
                }
                if let failure {
                    Text(failure).font(CompanionType.caption).foregroundStyle(.dsDanger)
                }
            }
            .foregroundStyle(.dsTextPrimary)
        }
    }

    private func symbol(_ option: ConfigOption) -> String {
        switch option.category {
        case "model": "cpu"
        case "thought_level": "brain"
        case "mode": "shield.lefthalf.filled"
        default: "slider.horizontal.3"
        }
    }

    private func choose(_ value: String, for option: ConfigOption) {
        Task { failure = await host.setConfigOption(option.id, to: value, in: sessionID) }
    }
}
