import ACP
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

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
/// `-nativeWindowFrame "x y width height"` (screen points, from the bottom left of the main screen)
/// moves the window first: a window other windows cover isn't drawn, so its frames would measure
/// nothing, and every isolated instance opens in the same place.
///
/// `-nativeOpenSession <agent id>/<session id>` selects that session as soon as its agent lists it.
/// Once it has loaded, it writes "loaded" to `-nativeOpenSessionLog <path>` (for a script to attach a
/// profiler), sends `-nativeOpenSessionPrompt <text>` as the user would, scrolls to the item
/// `-nativeRevealItemFromEnd <n>` items before the end as search does, and starts
/// `PlatformAutoScroll` when its launch arguments ask for it.
enum PerformanceDriver {
    static func run(model: AppModel) async {
        #if os(macOS)
        await placeWindow()
        #endif
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
        let fromEnd = defaults.integer(forKey: "nativeRevealItemFromEnd")
        if fromEnd > 0, session.state.items.count > fromEnd {
            session.transcriptReveal = TranscriptReveal(
                itemID: session.state.items[session.state.items.count - fromEnd].id)
        }
        #if os(macOS)
        PlatformAutoScroll.startIfRequested()
        #endif
        if let prompt = defaults.string(forKey: "nativeOpenSessionPrompt"), !prompt.isEmpty {
            session.draft = prompt
            await session.send()
        }
    }

    #if os(macOS)
    private static func placeWindow() async {
        let numbers = (UserDefaults.standard.string(forKey: "nativeWindowFrame") ?? "")
            .split(separator: " ").compactMap { Double($0) }
        guard numbers.count == 4 else { return }
        let main = { NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) } }
        guard await wait(for: { main() != nil }), let window = main() else { return }
        window.setFrame(NSRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]), display: true)
    }
    #endif

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
