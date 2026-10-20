import Foundation
import SwiftUI
import os

// TEMPORARY (launch performance work): switches for A/B measurements, each off unless its launch
// argument turns it on (`-lx.<name> YES`), and checkpoints logged only with `-launchCheckpoints YES`.
// Removed before the work is reported.
nonisolated enum LaunchExperiment {
    static func isOn(_ name: String) -> Bool {
        UserDefaults.standard.bool(forKey: "lx.\(name)")
    }

    static let noAgeTimeline = isOn("noAgeTimeline")
    static let noAgeA11y = isOn("noAgeA11y")
    static let noRowHelp = isOn("noRowHelp")
    static let noIconHelp = isOn("noIconHelp")
    static let noInlineCode = isOn("noInlineCode")
    static let noA11yActions = isOn("noA11yActions")
    static let noContextMenu = isOn("noContextMenu")
    static let noDoubleTap = isOn("noDoubleTap")
    static let noAccessory = isOn("noAccessory")
    static let noAgentIcon = isOn("noAgentIcon")
    static let noHover = isOn("noHover")
    static let emptyMenuItems = isOn("emptyMenuItems")
    static let noStatusBar = isOn("noStatusBar")
    static let noSidebar = isOn("noSidebar")
    static let noHome = isOn("noHome")
    static let noRowDrag = isOn("noRowDrag")
    static let noRowDrop = isOn("noRowDrop")
    static let plainRows = isOn("plainRows")
    static let noRowExtras = isOn("noRowExtras")
    static let rowNoButton = isOn("rowNoButton")
    static let rowNoTrailing = isOn("rowNoTrailing")
    static let rowNoLeading = isOn("rowNoLeading")
    static let rowNoChrome = isOn("rowNoChrome")
    static let rowNoA11y = isOn("rowNoA11y")

    private static let logs = UserDefaults.standard.bool(forKey: "launchCheckpoints")
    private static let logger = Logger(subsystem: "Native", category: "Launch")
    private static let signposter = OSSignposter(subsystem: "Native", category: .pointsOfInterest)
    private nonisolated(unsafe) static var done = false

    static func checkpoint(_ label: String) {
        guard logs, !done else { return }
        if label == "beforeWaiting" { done = true }
        let micro = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) / 1000
        var counts: (instructions: UInt64, cycles: UInt64) = (0, 0)
        _ = withUnsafeMutableBytes(of: &counts) { selfCounts?(1, $0.baseAddress, $0.count) }
        signposter.emitEvent("Launch checkpoint", "\(label, privacy: .public)")
        logger.notice("launch checkpoint \(label, privacy: .public) \(micro) us \(counts.instructions / 1000) Kinstr")
    }

    private typealias SelfCounts = @convention(c) (Int32, UnsafeMutableRawPointer?, Int) -> Int32
    private static let selfCounts: SelfCounts? = dlsym(
        dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOLOAD), "thread_selfcounts"
    ).map { unsafeBitCast($0, to: SelfCounts.self) }
}

extension View {
    /// TEMPORARY: applies `transform` unless the experiment switch is on.
    @ViewBuilder func lxUnless(_ off: Bool, _ transform: (Self) -> some View) -> some View {
        if off { self } else { transform(self) }
    }
}
