import CodeThemes
import Foundation
import NativePolicy

@testable import Native

#if !BEFORE
extension SettingsRegression {
    static func themeTryOn() async {
        let defaults = PreviewUserDefaults()
        let settings = SettingsPresentation()
        var policy = NativePolicy()
        let tryOn = ThemeTryOnModel(
            app: AppModel.preview(.empty), settings: settings,
            appearance: AppearanceModeController(defaults: PreviewUserDefaults()),
            plugins: PluginRegistry(previewing: []), defaults: defaults, policy: { policy })
        let saved = {
            [
                AppearancePreferences.lightCodeThemeKey, AppearancePreferences.darkCodeThemeKey,
                AppearancePreferences.lightToneKey, AppearancePreferences.darkToneKey,
            ].map { defaults.string(forKey: $0) ?? "-" }
        }
        let untouched = saved()
        settings.open(.appearance)
        tryOn.start()
        expect(tryOn.stage == .sample && !settings.isShown, "Try On without tasks opens the sample over Settings")
        expect(tryOn.trial?.highlighted == .native, "The list starts on the theme in use")
        tryOn.show(.dark)
        tryOn.highlight(CodeTheme.nord.id)
        tryOn.move(1)
        tryOn.move(-1)
        tryOn.setBackgrounds(.init(light: .wool, dark: .trueBlack))
        expect(tryOn.trial?.highlighted == .nord, "Arrows move the highlight and back")
        expect(saved() == untouched, "Trying writes nothing")
        tryOn.cancel()
        expect(saved() == untouched && !tryOn.isActive, "Cancel writes nothing")
        expect(settings.pane == .appearance && tryOn.keptNote == nil, "Cancel returns to Appearance")

        let undo = UndoManager()
        undo.groupsByEvent = false
        tryOn.start()
        tryOn.show(.dark)
        _ = tryOn.highlight(matching: "to")
        tryOn.show(.light)
        tryOn.highlight(CodeTheme.github.id)
        tryOn.setBackgrounds(.init(light: .wool, dark: .standard))
        undo.beginUndoGrouping()
        tryOn.keep(undoManager: undo)
        undo.endUndoGrouping()
        let kept = ["github", "tokyo-night", "wool", "standard"]
        expect(saved() == kept, "Keep writes both modes and the backgrounds: \(saved())")
        expect(settings.pane == .appearance && !tryOn.isActive, "Keep returns to Appearance")
        expect(
            tryOn.keptNote?.message
                == "Kept GitHub for light mode and Tokyo Night for dark mode. The terminal uses them too.",
            "The kept line names what changed, the listed mode first")
        expect(undo.undoActionName == "Code Theme", "Keep is named for Undo")
        undo.undo()
        expect(saved() == ["native", "native", "paper", "standard"], "Undo restores what was there")
        expect(tryOn.keptNote == nil, "Undo takes the kept line away")
        undo.redo()
        expect(saved() == kept, "Redo keeps them again")

        undo.removeAllActions()
        tryOn.start()
        tryOn.show(.dark)
        tryOn.highlight(CodeTheme.nord.id)
        undo.beginUndoGrouping()
        tryOn.keep(undoManager: undo)
        undo.endUndoGrouping()
        tryOn.undoKeep(undoManager: undo)
        expect(saved() == kept && !undo.canUndo, "The kept line's Undo restores and leaves nothing to undo twice")

        tryOn.start()
        tryOn.highlight(CodeTheme.dracula.id)
        tryOn.abandon()
        expect(saved() == kept && !tryOn.isActive, "Leaving for another task writes nothing")

        settings.open(.appearance)
        tryOn.start()
        tryOn.show(.dark)
        tryOn.highlight(CodeTheme.dracula.id)
        tryOn.setBackgrounds(.init(light: .paper, dark: .trueBlack))
        expect(tryOn.previewThemes?.dark == .dracula, "The window shows the tried theme")
        policy = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.appearance.codeTheme": "native"]))
        expect(tryOn.previewThemes == nil, "A code theme policy wins over the tried theme at once")
        tryOn.keep(undoManager: undo)
        expect(saved() == kept && !tryOn.isActive, "Keep cannot race a newly managed code theme or save backgrounds")
        tryOn.policyChanged()
        expect(saved() == kept && !tryOn.isActive, "A code theme policy mid-trial ends Try On, writing nothing")
        expect(settings.pane == .appearance, "Try On ended by policy returns to Appearance")
        tryOn.start()
        expect(!tryOn.isAvailable && !tryOn.isActive, "Try On stays shut while policy sets the code theme")

        // Try On lands on code: with none to recolor, from Settings or the View menu, it opens the sample.
        let populated = AppModel.preview(.populated)
        var historyReplies: [SessionKey: String] = [:]
        var opened: [SessionKey] = []
        let onTasks = ThemeTryOnModel(
            app: populated, settings: SettingsPresentation(),
            appearance: AppearanceModeController(defaults: PreviewUserDefaults()),
            plugins: PluginRegistry(previewing: []), defaults: PreviewUserDefaults(), policy: { NativePolicy() },
            loadSession: { key in
                opened.append(key)
                SessionModel.preview(in: populated, agent: key.agent.rawValue, id: key.id.rawValue)?
                    .previewExchange("Show it", reply: historyReplies[key] ?? "Done.")
            })
        onTasks.start()
        await finishTaskSearch(onTasks)
        expect(onTasks.stage == .sample, "With no task showing code, Settings opens the sample")
        onTasks.cancel()
        let tasks = populated.sessions.loadedSessions.filter { $0.parentID == nil && $0.origin == .user }
        guard tasks.count >= 2 else { return expect(false, "The populated preview has open tasks") }
        let (coded, plain) = (tasks[0], tasks[1])
        onTasks.start(on: plain.key)
        expect(onTasks.stage == .sample, "A task in view without code opens the sample")
        onTasks.cancel()
        coded.previewExchange("Show it", reply: "```swift\nlet answer = 42\n```", endedAgo: 0)
        onTasks.start()
        await finishTaskSearch(onTasks)
        expect(onTasks.stage == .task(coded.key), "Settings opens the latest task with code")
        expect(populated.selection == coded.key, "Try On shows the task it opened on")
        onTasks.cancel()
        onTasks.start(on: coded.key)
        expect(onTasks.stage == .task(coded.key), "A task in view with code is where Try On opens")
        onTasks.cancel()

        guard let project = populated.projects.all.first else { return expect(false, "A preview project exists") }
        let newest = SessionKey(agent: coded.key.agent, id: .init("try-on-newest"))
        let next = SessionKey(agent: coded.key.agent, id: .init("try-on-next"))
        for (key, age) in [(newest, 300.0), (next, 200.0)] {
            populated.catalog.add(
                .init(sessionId: key.id, cwd: project.path, updatedAt: .now.addingTimeInterval(age)),
                for: key.agent, in: project.id)
        }
        historyReplies[next] = "```swift\nlet restored = true\n```"
        opened = []
        onTasks.start()
        await finishTaskSearch(onTasks)
        expect(opened == [newest, next], "Search unopened catalog tasks newest first, skipping one without code")
        expect(onTasks.stage == .task(next), "A newer unopened task with code wins over an older open task")
        onTasks.cancel()

        // A relaunch has a populated catalog and no models. History is loaded without sending a prompt.
        for session in populated.sessions.loadedSessions { populated.sessions.remove(session) }
        opened = []
        onTasks.start()
        await finishTaskSearch(onTasks)
        expect(opened == [newest, next], "After relaunch, the catalog is still searched newest first")
        expect(onTasks.stage == .task(next), "Completed tasks with code are used after relaunch")
        onTasks.cancel()

        for session in populated.sessions.loadedSessions { populated.sessions.remove(session) }
        var resumeLoading: CheckedContinuation<Void, Never>?
        var searchPolicy = NativePolicy()
        let searching = ThemeTryOnModel(
            app: populated, settings: SettingsPresentation(),
            appearance: AppearanceModeController(defaults: PreviewUserDefaults()),
            plugins: PluginRegistry(previewing: []), defaults: PreviewUserDefaults(), policy: { searchPolicy },
            loadSession: { _ in await withCheckedContinuation { resumeLoading = $0 } })
        for managed in [false, true] {
            searching.start()
            for _ in 0..<1_000 {
                if resumeLoading != nil { break }
                await Task.yield()
            }
            expect(resumeLoading != nil, "History loading can suspend while Try On stays cancellable")
            let selection = populated.selection
            if managed {
                searchPolicy.appearanceCodeTheme = "nord"
                searching.policyChanged()
            } else {
                searching.cancel()
            }
            resumeLoading?.resume()
            resumeLoading = nil
            for _ in 0..<10 { await Task.yield() }
            expect(!searching.isActive && searching.stage == nil, "A late history result cannot reopen an ended trial")
            expect(populated.selection == selection, "Ending a history search preserves task selection")
        }

        var replaying: SessionModel?
        var replayPolicy = NativePolicy()
        let replaySearch = ThemeTryOnModel(
            app: populated, settings: SettingsPresentation(),
            appearance: AppearanceModeController(defaults: PreviewUserDefaults()),
            plugins: PluginRegistry(previewing: []), defaults: PreviewUserDefaults(), policy: { replayPolicy },
            loadSession: { key in
                let session = SessionModel.preview(
                    in: populated, agent: key.agent.rawValue, id: key.id.rawValue,
                    phase: key == newest ? .loading : .idle)
                if key == newest {
                    replaying = session
                } else if key == next {
                    session?.previewExchange("Show it", reply: "```swift\nlet older = true\n```", endedAgo: 0)
                }
            })
        replaySearch.start()
        for _ in 0..<1_000 {
            if replaying != nil { break }
            await Task.yield()
        }
        expect(replaySearch.stage == .findingTask, "A host open can return before its replay finishes")
        replaying?.previewExchange("Show it", reply: "```swift\nlet newest = true\n```", endedAgo: 0)
        replaying?.phase = .idle
        await finishTaskSearch(replaySearch)
        expect(replaySearch.stage == .task(newest), "Replayed code in the newest task beats the older candidate")
        replaySearch.cancel()

        // Models already loading must wait too, even if an early replay chunk contains code.
        replaying?.phase = .loading
        replaySearch.start()
        for _ in 0..<10 { await Task.yield() }
        expect(replaySearch.stage == .findingTask, "An already-loading model isn't inspected until replay finishes")
        replaySearch.cancel()
        replaying?.phase = .idle
        for _ in 0..<10 { await Task.yield() }
        expect(!replaySearch.isActive && replaySearch.stage == nil, "Cancel also ends a wait for host replay")

        if let replaying { populated.sessions.remove(replaying) }
        replaying = nil
        replaySearch.start()
        for _ in 0..<1_000 {
            if replaying != nil { break }
            await Task.yield()
        }
        replaying?.phase = .disconnected
        await finishTaskSearch(replaySearch)
        expect(replaySearch.stage == .task(next), "A failed replay with no code lets the next candidate load")
        replaySearch.cancel()

        replaying?.phase = .loading
        replaySearch.start()
        for _ in 0..<10 { await Task.yield() }
        replayPolicy.appearanceCodeTheme = "nord"
        replaySearch.policyChanged()
        replaying?.phase = .idle
        for _ in 0..<10 { await Task.yield() }
        expect(!replaySearch.isActive && replaySearch.stage == nil, "Policy also cancels a wait for host replay")
    }

    private static func finishTaskSearch(_ tryOn: ThemeTryOnModel) async {
        for _ in 0..<1_000 {
            if tryOn.stage != .findingTask { return }
            await Task.yield()
        }
        expect(false, "The inert task history search finishes")
    }
}
#endif
