import ACP
import SwiftUI

extension View {
    /// Runs `PerformanceDriver` in Debug builds and in Release builds compiled with `NATIVE_PERF`.
    @ViewBuilder func performanceDriver(_ model: AppModel) -> some View {
        #if DEBUG || NATIVE_PERF
        task { await PerformanceDriver.run(model: model) }
        #else
        self
        #endif
    }
}

#if DEBUG || NATIVE_PERF
/// Drives the app for measurements without an accessibility client, which would make SwiftUI keep
/// its accessibility tree current every frame, a cost people without one never pay
/// (docs/performance.md, "Long transcripts").
///
/// `-nativeOpenSession <agent id>/<session id>` selects that session as soon as its agent lists it.
/// Once it has loaded, it writes "loaded" to `-nativeOpenSessionLog <path>` (for a script to attach a
/// profiler), sends `-nativeOpenSessionPrompt <text>` as the user would, and starts
/// `PlatformAutoScroll` when its launch arguments ask for it.
enum PerformanceDriver {
    static func run(model: AppModel) async {
        guard let target = UserDefaults.standard.string(forKey: "nativeOpenSession"),
            let slash = target.firstIndex(of: "/")
        else { return }
        let key = SessionKey(
            agent: AgentDefinition.ID(rawValue: String(target[..<slash])),
            id: SessionID(String(target[target.index(after: slash)...])))
        guard await wait(for: { model.catalog.lookup(key) != nil }) else { return }
        model.selection = key
        guard await wait(for: { model.sessions.session(key).map { $0.phase != .loading } ?? false }),
            let session = model.sessions.session(key)
        else { return }
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "nativeOpenSessionLog"), !path.isEmpty {
            FileManager.default.createFile(atPath: path, contents: Data("loaded\n".utf8))
        }
        #if os(macOS)
        PlatformAutoScroll.startIfRequested()
        #endif
        if let prompt = defaults.string(forKey: "nativeOpenSessionPrompt"), !prompt.isEmpty {
            session.draft = prompt
            await session.send()
        }
    }

    /// Whether `condition` came true within a minute.
    private static func wait(for condition: () -> Bool) async -> Bool {
        for _ in 0..<600 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
#endif
