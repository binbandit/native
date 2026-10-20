import Foundation
import NativeOrchestration

extension MacHost {
    /// The guides Native's tools serve (`list_skills`, `get_skill`): the copies of docs/setup.md and
    /// docs/plugins.md in the app this host came with. The helper runs from inside Native.app
    /// (`Contents/Library/LoginItems/`); a host on its own has none, and offers neither tool.
    static func bundledSkills(helper: Bundle = .main) -> [NativeSkill] {
        let app = helper.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app", let bundle = Bundle(url: app) else { return [] }
        return NativeSkill.bundled(in: bundle)
    }
}
