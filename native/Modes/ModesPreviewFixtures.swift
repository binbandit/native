#if NATIVE_PREVIEWS_WIP
import ACP
import Foundation

/// Mode controls for previews: a task's mode read from memory (`PreviewUserDefaults`), never from
/// the user's choices, for a session that runs nothing.
enum ModesPreviewFixtures {
    /// A task on Claude Code; in Plan Mode when `planning`, which reads as the Plan mode.
    static func control(planning: Bool = false, working: Bool = false) -> TaskModeControl? {
        let app = AppModel.preview()
        let options = planning ? ComposerPreviewFixtures.planModeOptions : ComposerPreviewFixtures.configOptions
        guard
            let session = SessionModel.preview(
                in: app, title: "Queue follow-ups while a turn runs", phase: working ? .prompting : .idle,
                configOptions: options)
        else { return nil }
        let defaults = PreviewUserDefaults()
        return TaskModeControl(
            session: session, modes: TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults))
    }
}
#endif
