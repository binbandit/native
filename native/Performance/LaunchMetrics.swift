import CoreFoundation
import Darwin
import Foundation
import os

/// How long launch takes, from the moment the process started: Points of Interest signposts for
/// Instruments, and one log line per milestone that `just perf` reads, with the wall-clock time,
/// the CPU time the main thread and the whole process spent getting there, and the instructions
/// the main thread ran (`launch firstFrame 212 ms, main 150 ms cpu, process 190 ms cpu, 900 M
/// instructions on main`). CPU time is steadier than wall-clock time on a busy Mac, but still
/// doubles when the main thread lands on efficiency cores; instructions don't depend on the core.
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
        logger.notice(
            "launch \(milestone.rawValue, privacy: .public) \(milliseconds) ms, main \(cpuMilliseconds(CLOCK_THREAD_CPUTIME_ID)) ms cpu, process \(cpuMilliseconds(CLOCK_PROCESS_CPUTIME_ID)) ms cpu, \(mainInstructions.map(String.init) ?? "?", privacy: .public) M instructions on main"
        )
    }

    /// Marks `milestone` once the frame showing what just appeared is on screen: when the main run
    /// loop next goes to sleep, after Core Animation has committed that frame and nothing else is
    /// waiting on the main thread. Call it from `onAppear`.
    static func markOnScreen(_ milestone: Milestone) {
        guard !reached.contains(milestone) else { return }
        // After every other before-waiting observer, Core Animation's commit included.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, .max) {
            _, _ in
            MainActor.assumeIsolated {
                checkpoint("beforeWaiting"); mark(milestone)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// CPU time used so far: by the calling thread (the main thread, since milestones are marked
    /// there) or the whole process.
    private static func cpuMilliseconds(_ clock: clockid_t) -> Int {
        Int(clock_gettime_nsec_np(clock) / 1_000_000)
    }

    /// Millions of instructions the calling thread has run, from the CPU's own counters, which
    /// cost the same on any core. `thread_selfcounts` isn't in the SDK (Instruments' counters use
    /// it), so it's looked up and left out where it's missing.
    private static var mainInstructions: UInt64? {
        guard let threadSelfCounts else { return nil }
        var counts: (instructions: UInt64, cycles: UInt64) = (0, 0)
        let result = withUnsafeMutableBytes(of: &counts) { threadSelfCounts(1, $0.baseAddress, $0.count) }
        return result == 0 ? counts.instructions / 1_000_000 : nil
    }

    private typealias ThreadSelfCounts = @convention(c) (Int32, UnsafeMutableRawPointer?, Int) -> Int32
    private static let threadSelfCounts: ThreadSelfCounts? = {
        let kernel = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOLOAD)
        return dlsym(kernel, "thread_selfcounts").map { unsafeBitCast($0, to: ThreadSelfCounts.self) }
    }()

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
