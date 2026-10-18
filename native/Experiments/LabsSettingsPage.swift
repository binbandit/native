import Experiments
import SwiftUI

extension SettingsPane.ID {
    static let labs = Self("labs")
}

extension SettingsPane {
    /// Settings ▸ Labs: Native's experiments and enabled plugins', to try and turn off again.
    static let labs = SettingsPane(
        id: .labs,
        title: "Labs",
        systemImage: "flask",
        group: .extensions,
        order: 0,
        keywords: ["experiments", "experimental", "beta", "flags", "preview"],
        searchEntries: {
            ExperimentStore.shared.catalog.experiments.map { experiment in
                SettingsSearchEntry(
                    id: LabsSettingsPage.rowID(experiment.id),
                    title: experiment.title,
                    description: experiment.summary,
                    keywords: ["experiment", "labs", experiment.stage.title]
                )
            }
        },
        content: { LabsSettingsPage() }
    )
}

/// the reference app's Experimental page for Native's experiments: one row per experiment with its stage,
/// what it changes and its control, conflicts called out above, and Reset All. Every change can be
/// undone with ⌘Z.
struct LabsSettingsPage: View {
    static func rowID(_ id: ExperimentID) -> SettingsRowID {
        SettingsRowID("labs.\(id.rawValue)")
    }

    @Environment(\.experimentStore) private var storeOverride
    @Environment(PluginRegistry.self) private var registry
    @Environment(\.undoManager) private var undoManager

    private var store: ExperimentStore {
        storeOverride ?? .shared
    }

    var body: some View {
        SettingsPage {
            SettingsHeader(
                title: "Labs",
                description: description
            ) {
                Button("Reset All", systemImage: "arrow.counterclockwise", action: resetAll)
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .disabled(store.changed.isEmpty)
                    .help("Turn every experiment back to its default")
            }
            ForEach(store.conflicts, id: \.self) { conflict in
                LabsConflictBanner(conflict: conflict, catalog: store.catalog) { id in
                    change(id, to: nil, actionName: "Turn Off Experiment")
                }
            }
            let sections = LabsSection.sections(catalog: store.catalog, problems: registry.experimentProblems)
            if sections.isEmpty {
                EmptyStateView(
                    "No experiments right now",
                    systemImage: "flask",
                    message: "New features and designs show up here to try before they're finished."
                )
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        if let name = section.pluginName {
                            SettingsSubheading(name, note: "From the \(name) plugin. Turning the plugin off removes these.")
                        }
                        SettingsRowGroup {
                            ForEach(section.experiments) { experiment in
                                row(for: experiment)
                            }
                            ForEach(section.problems) { problem in
                                LabsProblemRow(problem: problem)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(for experiment: ExperimentDescriptor) -> some View {
        LabsExperimentRow(
            id: Self.rowID(experiment.id),
            experiment: experiment,
            value: store.saved.value(for: experiment.id) ?? experiment.defaultValue,
            needsRelaunch: store.needsRelaunch(experiment.id),
            conflict: store.conflicts.first { $0.sources.contains(.experiment(experiment.id)) }
        ) { value in
            change(experiment.id, to: value, actionName: "Change \(experiment.title)")
        }
    }

    private var description: Text {
        let reassurance = Text("Turn one off anytime.").fontWeight(.medium)
        return Text("Features and designs that aren't finished yet. They may change or go away. \(reassurance)")
    }

    /// Changes one experiment, undoably.
    private func change(_ id: ExperimentID, to value: StoredValue?, actionName: String) {
        let before = store.saved.overrides
        store.setValue(value, for: id)
        registerUndo(restoring: before, actionName: actionName)
    }

    private func resetAll() {
        let before = store.saved.overrides
        store.resetAll()
        registerUndo(restoring: before, actionName: "Reset All Experiments")
    }

    private func registerUndo(restoring overrides: [ExperimentID: StoredValue], actionName: String) {
        guard let undoManager, overrides != store.saved.overrides else { return }
        Self.registerUndo(on: undoManager, store: store, restoring: overrides)
        undoManager.setActionName(actionName)
    }

    /// Undo puts back `overrides` and registers putting back what they replaced, so redo works too.
    private static func registerUndo(
        on undoManager: UndoManager, store: ExperimentStore, restoring overrides: [ExperimentID: StoredValue]
    ) {
        let replaced = store.saved.overrides
        undoManager.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                store.setOverrides(overrides)
                registerUndo(on: undoManager, store: store, restoring: replaced)
            }
        }
    }
}
