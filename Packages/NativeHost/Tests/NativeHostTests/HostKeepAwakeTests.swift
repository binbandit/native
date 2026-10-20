import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

/// Power assertions without touching the Mac's: what's held, and a power source tests can switch.
final class FakePowerBackend: HostPowerBackend {
    private let state = Mutex<(held: Set<PowerAssertionKind>, power: PowerState, observers: [@Sendable () -> Void])>(
        ([], PowerState(), []))

    var held: Set<PowerAssertionKind> {
        state.withLock { $0.held }
    }

    func hold(_ kinds: Set<PowerAssertionKind>, name: String) -> Set<PowerAssertionKind> {
        state.withLock { $0.held = kinds }
        return kinds
    }

    func powerState() -> PowerState {
        state.withLock { $0.power }
    }

    func observePowerChanges(_ onChange: @escaping @Sendable () -> Void) {
        state.withLock { $0.observers.append(onChange) }
    }

    /// Switches the power source, as unplugging the Mac would.
    func switchPower(to power: PowerState) {
        let observers = state.withLock {
            $0.power = power
            return $0.observers
        }
        for observer in observers {
            observer()
        }
    }
}

@Suite("Keeping awake in the host", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostKeepAwakeTests {
    static let awake: Set<PowerAssertionKind> = [.preventIdleSleep, .preventSystemSleep]

    /// Waits up to `within` for `condition`, polling.
    static func eventually(within: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + within
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    @Test("While agents work: held while any session works, released when none does, never the display")
    func whileAgentsWork() {
        let backend = FakePowerBackend()
        let engine = HostKeepAwakeEngine(backend: backend, policy: KeepAwakePolicy(mode: .whileAgentsWork))
        engine.start(workingAgents: 0)
        #expect(backend.held.isEmpty)
        #expect(engine.status.reason == .waitingForAgents)
        engine.setWorkingAgents(2)
        #expect(backend.held == Self.awake)
        #expect(engine.state.status.workingAgents == 2)
        engine.setWorkingAgents(0)
        #expect(backend.held.isEmpty)
    }

    @Test("Off holds nothing however busy; On and the display setting hold what they say")
    func modes() {
        let backend = FakePowerBackend()
        let engine = HostKeepAwakeEngine(backend: backend, policy: KeepAwakePolicy())
        var changes: [HostKeepAwakeState] = []
        engine.onChange = { changes.append($0) }
        engine.start(workingAgents: 3)
        #expect(backend.held.isEmpty)
        engine.setPolicy(KeepAwakePolicy(mode: .on, keepsDisplayOn: true))
        #expect(backend.held == Self.awake.union([.preventDisplaySleep]))
        #expect(changes.last?.status.reason == .alwaysOn)
        engine.setPolicy(KeepAwakePolicy(mode: .off))
        #expect(backend.held.isEmpty)
    }

    @Test("On battery the rule decides, and switching the power source applies it at once")
    func battery() async {
        let backend = FakePowerBackend()
        backend.switchPower(to: PowerState(isOnBattery: true, batteryLevel: 0.5))
        let engine = HostKeepAwakeEngine(
            backend: backend, policy: KeepAwakePolicy(mode: .on, battery: .pluggedInOnly))
        engine.start(workingAgents: 0)
        #expect(backend.held.isEmpty)
        #expect(engine.status.reason == .pausedOnBattery)
        backend.switchPower(to: PowerState(isOnBattery: false, batteryLevel: 0.5))
        #expect(await Self.eventually { backend.held == Self.awake })
    }

    @Test("A timer keeps it awake until it runs out")
    func timer() async {
        let backend = FakePowerBackend()
        let engine = HostKeepAwakeEngine(
            backend: backend, policy: KeepAwakePolicy(awakeUntil: .now.addingTimeInterval(0.3)))
        engine.start(workingAgents: 0)
        #expect(backend.held == Self.awake)
        #expect(engine.status.reason == .timer)
        #expect(await Self.eventually { backend.held.isEmpty })
        #expect(engine.status.reason == .off)
    }

    @Test("A host without a backend says it can't keep the machine awake")
    func unsupported() {
        let engine = HostKeepAwakeEngine(backend: nil, policy: KeepAwakePolicy(mode: .on))
        engine.start(workingAgents: 0)
        #expect(!engine.state.isSupported)
        #expect(engine.state.held.isEmpty)
    }
}
