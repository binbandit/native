import Foundation
import IOKit.pwr_mgt
import os
import Synchronization

/// The power assertions held right now. Setting a new set takes the missing ones and releases the
/// rest; releasing on deinit, and the system releasing a dead process's assertions, mean the Mac is
/// never left awake by mistake. `pmset -g assertions` lists them under `name`.
nonisolated final class PowerAssertions: Sendable {
    private let held = Mutex<[PowerAssertionKind: IOPMAssertionID]>([:])
    private let logger = Logger(subsystem: "Native", category: "KeepAwake")

    deinit {
        set([], name: "")
    }

    var kinds: Set<PowerAssertionKind> {
        held.withLock { Set($0.keys) }
    }

    /// Holds exactly `kinds`, named `name` (renaming the ones already held). Returns what's held,
    /// which falls short of `kinds` if the system refused an assertion.
    @discardableResult
    func set(_ kinds: Set<PowerAssertionKind>, name: String) -> Set<PowerAssertionKind> {
        held.withLock { held in
            for (kind, id) in held where !kinds.contains(kind) {
                IOPMAssertionRelease(id)
                held[kind] = nil
            }
            for (_, id) in held {
                IOPMAssertionSetProperty(id, kIOPMAssertionNameKey as CFString, name as CFString)
            }
            for kind in kinds where held[kind] == nil {
                var id = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(kind.type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id)
                if result == kIOReturnSuccess {
                    held[kind] = id
                } else {
                    logger.error("Couldn't take power assertion \(kind.type, privacy: .public): \(result)")
                }
            }
            return Set(held.keys)
        }
    }
}
