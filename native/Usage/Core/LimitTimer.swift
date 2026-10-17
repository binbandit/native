import Foundation

/// Runs an action once at a wall-clock time. Sleeps on the continuous clock, which keeps counting
/// while the Mac sleeps, so a reset that passed during sleep fires on wake rather than hours late.
/// Wall-clock changes aren't seen; owners reschedule when the system clock changes.
final class LimitTimer {
    private var task: Task<Void, Never>?

    func schedule(at date: Date?, now: Date, action: @escaping () -> Void) {
        task?.cancel()
        task = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSince(now))
        task = Task {
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1), clock: .continuous)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
