import NativeTelemetry

/// Notices when the main thread stops answering: a background task asks it to run an empty block
/// every second, and a wait of two seconds or more is recorded as a hang.
enum TelemetryHangWatchdog {
    static let threshold = Duration.seconds(2)

    static func start() {
        Task.detached(priority: .utility) {
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let asked = clock.now
                await MainActor.run {}
                let waited = clock.now - asked
                if waited >= threshold {
                    Telemetry.record(.hangDetected(duration: waited))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
