import Modes
import SwiftUI

/// The modes a project shares from its `.native/modes/` folder, each with what it applies and
/// what in its file was ignored, then each file that couldn't be used, with why and Reload.
struct ProjectModesList: View {
    let root: URL
    /// Starts one of the user's own modes from this one.
    let duplicate: (Mode) -> Void

    @State private var shownInstructions: Set<Mode.ID> = []
    private let library = ModeLibrary.shared

    var body: some View {
        let modes = library.projectModes(at: root)
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if !modes.modes.isEmpty {
                SettingsRowGroup {
                    ForEach(modes.modes, id: \.mode.id) { parsed in
                        row(parsed)
                    }
                }
            }
            ForEach(modes.problems, id: \.file) { problem in
                NoticeBanner(
                    tone: .warning, title: "\(ModeFile.folder)/\(problem.file) isn't a mode", detail: problem.reason,
                    footnote: "The project's other modes still work. Fix the file, then Reload."
                ) {
                    Button("Reload") { library.refresh(projectAt: root) }
                        .buttonStyle(.ds(.secondary))
                }
            }
        }
    }

    private func row(_ parsed: ModeFile.Parsed) -> some View {
        let mode = parsed.mode
        let detail = ([ModeSettingsText.describe(mode)] + parsed.warnings).joined(separator: "\n")
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsRow(mode.name, icon: mode.symbol, description: Text(mode.summary), detail: Text(detail)) {
                HStack(spacing: DS.Space.sm) {
                    Button(shownInstructions.contains(mode.id) ? "Hide Instructions" : "Instructions") {
                        shownInstructions.formSymmetricDifference([mode.id])
                    }
                    Button("Duplicate") { duplicate(mode) }
                        .help("Make a mode of your own from it, for every project")
                }
            }
            if shownInstructions.contains(mode.id) {
                ModeInstructionsText(mode: mode)
            }
        }
    }
}
