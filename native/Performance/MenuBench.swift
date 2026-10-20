import Foundation
import NativeCommands
import os

#if canImport(AppKit)
import AppKit
#endif

/// Temporary measurement of what the main menu costs, at launch and per focus change. Off unless
/// its launch arguments ask; removed once the numbers are in docs/performance.md.
@MainActor
enum MenuBench {
    /// `-menuBenchNoMenus YES` leaves the menu bar's own items out, to measure what they cost.
    static var keepsMenus: Bool {
        #if DEBUG || NATIVE_PERF
        !UserDefaults.standard.bool(forKey: "menuBenchNoMenus")
        #else
        true
        #endif
    }

    #if DEBUG || NATIVE_PERF
    private static let logger = Logger(subsystem: "Native", category: "MenuBench")
    static var itemBodies = 0
    private static var isStarted = false

    static func installLaunchObservers() {
        for name in [NSApplication.willFinishLaunchingNotification, NSApplication.didFinishLaunchingNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { note in
                let label = note.name.rawValue
                MainActor.assumeIsolated {
                    logger.notice(
                        "bench \(label, privacy: .public) \(instructions() / 1_000_000) M bodies \(itemBodies)")
                }
            }
        }
    }

    /// `-menuBenchSwitches N` alternates the selection between the first two tasks N times once
    /// launch settles; `-menuBenchRebinds N` gives Appearance: Dark a shortcut and takes it away N
    /// times, which invalidates every item that reads shortcuts while one item's changes. Both log
    /// the main thread's instructions (K) and the menu items' bodies per change.
    static func startSwitching(model: AppModel) {
        guard !isStarted else { return }
        isStarted = true
        let switches = UserDefaults.standard.integer(forKey: "menuBenchSwitches")
        let rebinds = UserDefaults.standard.integer(forKey: "menuBenchRebinds")
        guard switches > 0 || rebinds > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            let keys = model.sessionList.prefix(2).map(\.id)
            if switches > 0, keys.count == 2 {
                for index in 0..<(switches + 4) {
                    await measure("switch \(index)") { model.selection = keys[index % 2] }
                }
            }
            let registry = CommandRegistry.shared
            for index in 0..<rebinds {
                await measure("rebind \(index)") {
                    if index % 2 == 0 {
                        registry.assign(
                            KeyShortcut(.character("j"), modifiers: [.command, .control, .option]),
                            to: .appearanceDark, resolving: .replace)
                    } else {
                        registry.reset(.appearanceDark)
                    }
                }
            }
            registry.reset(.appearanceDark)
            logger.notice("bench done")
        }
    }

    private static func measure(_ label: String, _ change: () -> Void) async {
        let bodies = itemBodies
        let start = instructions()
        change()
        try? await Task.sleep(for: .milliseconds(600))
        let used = (instructions() - start) / 1000
        logger.notice(
            "bench \(label, privacy: .public) \(used) K bodies \(itemBodies - bodies) active \(NSApp.isActive)")
    }

    private static func instructions() -> UInt64 {
        guard let threadSelfCounts else { return 0 }
        var counts: (instructions: UInt64, cycles: UInt64) = (0, 0)
        let result = withUnsafeMutableBytes(of: &counts) { threadSelfCounts(1, $0.baseAddress, $0.count) }
        return result == 0 ? counts.instructions : 0
    }

    private typealias ThreadSelfCounts = @convention(c) (Int32, UnsafeMutableRawPointer?, Int) -> Int32
    private static let threadSelfCounts: ThreadSelfCounts? = {
        let kernel = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOLOAD)
        return dlsym(kernel, "thread_selfcounts").map { unsafeBitCast($0, to: ThreadSelfCounts.self) }
    }()
    #endif
}
