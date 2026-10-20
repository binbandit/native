import Modes
import SwiftUI

/// The modes as a submenu, each checkable: the More menu's stand-in for the Mode pill when the
/// composer has no room for it.
struct ModeMenu: View {
    let control: TaskModeControl

    @Environment(SettingsPresentation.self) private var settings: SettingsPresentation?

    var body: some View {
        let current = control.current
        let catalog = control.catalog
        Menu("Mode: \(current.name)", systemImage: current.symbol) {
            section(catalog.builtIn, current: current.id)
            if !catalog.custom.isEmpty {
                Section("Your modes") { section(catalog.custom, current: current.id) }
            }
            if !catalog.project.isEmpty {
                Section(control.projectName.map { "From \($0)" } ?? "From the project") {
                    section(catalog.project, current: current.id)
                }
            }
            if let settings {
                Divider()
                Button("Edit Modes…") { settings.open(.modes) }
            }
        }
    }

    private func section(_ modes: [Mode], current: Mode.ID) -> some View {
        ForEach(modes) { mode in
            Toggle(isOn: Binding(get: { mode.id == current }, set: { _ in control.select(mode.id) })) {
                Label(mode.name, systemImage: mode.symbol)
                Text(mode.summary)
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Mode menu") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            if let build = ModesPreviewFixtures.control(), let plan = ModesPreviewFixtures.control(planning: true) {
                Menu("More") { ModeMenu(control: build) }
                Menu("More") { ModeMenu(control: plan) }
            }
        }
        .fixedSize()
    }
    .environment(SettingsPresentation())
}
#endif
