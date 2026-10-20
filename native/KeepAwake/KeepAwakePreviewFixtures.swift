#if NATIVE_PREVIEWS_WIP
import Foundation
import NativeHostProtocol

/// Keep-awake previews: controllers whose engine holds no power assertion, so a preview never keeps
/// the Mac awake. The engine answers with the status a real one would give.
enum KeepAwakePreviewFixtures {
    /// Kept awake while agents work, two of them working now.
    static func working() -> KeepAwakeController {
        controller(
            mode: .whileAgentsWork,
            status: KeepAwakeStatus(reason: .agentsWorking, workingAgents: 2, assertions: [.preventIdleSleep]))
    }

    /// A timer running for two hours, keeping the display on too.
    static func timer() -> KeepAwakeController {
        let until = Date.now.addingTimeInterval(2 * 3600)
        let controller = controller(
            mode: .off,
            status: KeepAwakeStatus(
                reason: .timer, until: until, assertions: [.preventIdleSleep, .preventDisplaySleep]))
        controller.stayAwake(for: .seconds(2 * 3600))
        controller.keepsDisplayOn = true
        return controller
    }

    /// Would keep awake, but the Mac is on battery.
    static func paused() -> KeepAwakeController {
        controller(mode: .on, status: KeepAwakeStatus(reason: .pausedOnBattery))
    }

    static func off() -> KeepAwakeController {
        controller(mode: .off, status: .off)
    }

    private static func controller(mode: KeepAwakeMode, status: KeepAwakeStatus) -> KeepAwakeController {
        let controller = KeepAwakeController(
            engine: PreviewKeepAwakeEngine(status: status), defaults: PreviewUserDefaults())
        controller.setMode(mode)
        return controller
    }
}

/// Reports a fixed status and holds nothing.
final class PreviewKeepAwakeEngine: KeepAwakeEngine {
    var onChange: ((KeepAwakeStatus) -> Void)?
    private let status: KeepAwakeStatus

    init(status: KeepAwakeStatus) {
        self.status = status
    }

    func apply(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity) -> KeepAwakeStatus { status }
    func stop() {}
}
#endif
