import Foundation

/// How the status bar prints memory and CPU, everywhere it prints them (the segment, its tooltip
/// and the process table), so the numbers always read the same.
nonisolated enum ResourceFormat {
    /// "745.7 MB", "1.42 GB", as Activity Monitor writes memory.
    static func memory(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .memory))
    }

    /// Percent of one core: one decimal below 10% so idle processes don't all read 0%.
    static func cpu(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(percent < 10 ? 1 : 0)))
    }

    /// Memory as a share of the Mac's, for the tooltip ("3% of 64 GB").
    static func shareOfPhysicalMemory(_ bytes: UInt64) -> String {
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return "" }
        let share = Double(bytes) / Double(total)
        return "\(share.formatted(.percent.precision(.fractionLength(share < 0.1 ? 1 : 0)))) of \(memory(total))"
    }
}
