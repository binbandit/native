import CoreFoundation
import Darwin
import Foundation
import os

/// How long launch takes, from the moment the process started: Points of Interest signposts for
/// Instruments, and one log line per milestone (`launch firstFrame 212 ms`) that `just perf` reads.
/// The bar is half a Dock bounce, so launch feels instant (`docs/performance.md`).
@MainActor
enum LaunchMetrics {
    enum Milestone: String {
        /// `NativeApp.init`: the binary is loaded and Swift code runs.
        case appInit
        /// The main window's first frame is on screen.
        case firstFrame
        /// The sidebar's rows are on screen and the main thread is free to take a click.
        case sidebarInteractive
        /// Agents are checked and the default one is running, so New Session doesn't wait.
        case agentsReady
    }

    private static let signposter = OSSignposter(subsystem: "Native", category: .pointsOfInterest)
    private static let logger = Logger(subsystem: "Native", category: "Launch")
    private static var reached: Set<Milestone> = []
    private static var interval: OSSignpostIntervalState?

    /// Marks `milestone` now.
    static func mark(_ milestone: Milestone) {
        guard reached.insert(milestone).inserted else { return }
        let milliseconds = Int(Date.now.timeIntervalSince(processStart) * 1000)
        switch milestone {
        case .appInit:
            interval = signposter.beginInterval("Launch")
        case .sidebarInteractive:
            interval.map { signposter.endInterval("Launch", $0) }
        case .firstFrame, .agentsReady:
            break
        }
        signposter.emitEvent("Launch milestone", "\(milestone.rawValue, privacy: .public)")
        logger.notice("launch \(milestone.rawValue, privacy: .public) \(milliseconds) ms")
    }

    /// Marks `milestone` once the frame showing what just appeared is on screen: when the main run
    /// loop next goes to sleep, after Core Animation has committed that frame and nothing else is
    /// waiting on the main thread. Call it from `onAppear`.
    static func markOnScreen(_ milestone: Milestone) {
        guard !reached.contains(milestone) else { return }
        // After every other before-waiting observer, Core Animation's commit included.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, .max) {
            _, _ in
            MainActor.assumeIsolated { mark(milestone) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// When the kernel started this process, which is as close to the Dock click as an app can see.
    private static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return .now }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()
}
