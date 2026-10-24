/// Converts process CPU time to a share of the sampling machine's total CPU capacity.
public enum ProcessCPUUsage {
    /// CPU and elapsed time must use the same units. The processor count belongs to the machine
    /// being sampled, which may differ from the client displaying the result.
    public static func percent(cpuTime: UInt64, elapsedTime: UInt64, processorCount: Int) -> Double? {
        guard elapsedTime > 0, processorCount > 0 else { return nil }
        return min(100, Double(cpuTime) / Double(elapsedTime) * 100 / Double(processorCount))
    }

    /// Combines percentages that already use the same machine's total capacity.
    public static func total(_ percentages: some Sequence<Double>) -> Double {
        // Processes are read in sequence, so sampling skew can briefly push a busy total over 100.
        min(100, percentages.reduce(0, +))
    }
}
