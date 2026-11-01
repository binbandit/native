import Modes
import SwiftUI

struct NewTasksModeRow: View {
    var library = ModeLibrary.shared
    var project: Project?
    @Environment(\.undoManager) private var undoManager
    @State private var showsSource = false

    private var local: Mode.ID? { project.flatMap { library.startingOverride(forProjectAt: $0.url) } }
    private var localMode: Mode? { local.flatMap { catalog.mode($0) } }
    private var globalMode: Mode? { library.catalog(forProjectAt: nil).mode(library.defaultMode) }
    private var current: Mode { library.startingMode(forProjectAt: project?.url) }
    private var catalog: ModeCatalog { library.catalog(forProjectAt: project?.url) }
    private var usesPersonal: Bool { globalMode != nil && library.defaultMode != .build }
    private var options: [SettingsSelect<Mode.ID?>.Option] {
        var values: [SettingsSelect<Mode.ID?>.Option] =
            project == nil
            ? [] : [.init(value: nil, title: "Default (\(library.startingMode.name))")]
        values += catalog.all.map { .init(value: $0.id, title: $0.name) }
        if let stored = project == nil ? library.defaultMode : local, catalog.mode(stored) == nil {
            values.append(.init(value: stored, title: "\(stored.rawValue) (unavailable)"))
        }
        return values
    }
    private var receipt: NewTasksSettingReceipt {
        NewTasksSettingReceipt(
            title: "Mode", context: project.map { "in \($0.name)" } ?? "for all projects",
            value: current.name,
            source: localMode != nil
                ? .project(project?.name ?? "Project") : usesPersonal ? .user : .native,
            layers: [
                .init(
                    name: project?.name ?? "Project", symbol: "folder", value: localMode?.name ?? local?.rawValue,
                    wins: localMode != nil, overridden: local != nil && localMode == nil),
                .init(
                    name: "You", symbol: "person",
                    value: library.defaultMode == .build ? nil : globalMode?.name ?? library.defaultMode.rawValue,
                    wins: localMode == nil && usesPersonal,
                    overridden: library.defaultMode != .build && (localMode != nil || globalMode == nil)),
                .init(
                    name: "Native", symbol: "app", value: "Build", wins: localMode == nil && !usesPersonal),
            ],
            note:
                "The starting mode applies its settings after the agent defaults. A missing mode follows All projects.")
    }

    var body: some View {
        SettingsRow(id: .modesDefault, "Mode") {
            NewTasksSourceControl(receipt: receipt, showsSource: $showsSource) {
                NewTasksValueMenu(
                    label: "Mode",
                    selection: Binding<Mode.ID?>(
                        get: { project == nil ? library.defaultMode : local },
                        set: {
                            library.setStartingMode($0, forProjectAt: project?.url, undoManager: undoManager)
                        }),
                    options: options,
                    isDefault: project == nil ? library.defaultMode == .build : local == nil
                )
            }
            .contextMenu {
                Button("Why This Value…") { showsSource = true }
                Button("Reset") {
                    library.setStartingMode(nil, forProjectAt: project?.url, undoManager: undoManager)
                }
            }
        }
        .task(id: project?.id) {
            if let project { await library.finishReading(projectAt: project.url) }
        }
    }
}

#if DEBUG
#Preview("New Tasks - Mode") {
    DSPreviewPair {
        SettingsRowGroup { NewTasksModeRow(library: ModeLibrary(defaults: PreviewUserDefaults())) }
            .settingsPreviewPage()
    }.environment(\.settingsPlainly, true)
}
#endif
