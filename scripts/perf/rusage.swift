// Samples processes' resource usage over an interval, from the kernel's per-process counters
// (`proc_pid_rusage`), so no sudo is needed: CPU %, idle and interrupt wakeups per second, energy
// in milliwatts and physical footprint (what Activity Monitor calls Memory).
//
//   rusage <seconds> <label>=<pid>[,<pid>…] …
//
// Each label's pids are summed, for an app plus its children. Prints one tab-separated row per label.
import Darwin
import Foundation

struct Sample {
    var cpu: UInt64 = 0, idle: UInt64 = 0, interrupt: UInt64 = 0, energy: UInt64 = 0, footprint: UInt64 = 0
    var alive = 0

    mutating func add(_ pid: pid_t) {
        var info = rusage_info_v6()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        guard status == 0 else { return }
        alive += 1
        cpu += info.ri_user_time + info.ri_system_time
        idle += info.ri_pkg_idle_wkups
        interrupt += info.ri_interrupt_wkups
        energy += info.ri_energy_nj
        footprint += info.ri_phys_footprint
    }
}

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let toNanoseconds = Double(timebase.numer) / Double(timebase.denom)

let arguments = CommandLine.arguments.dropFirst()
guard let seconds = arguments.first.flatMap(Double.init), arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: rusage <seconds> <label>=<pid>[,<pid>…] …\n".utf8))
    exit(2)
}
let groups: [(String, [pid_t])] = arguments.dropFirst().map { argument in
    let parts = argument.split(separator: "=", maxSplits: 1)
    let pids = (parts.count > 1 ? parts[1] : parts[0]).split(separator: ",").compactMap { pid_t($0) }
    return (String(parts[0]), pids)
}

func sample() -> [Sample] {
    groups.map { _, pids in pids.reduce(into: Sample()) { $0.add($1) } }
}

let before = sample()
let start = DispatchTime.now().uptimeNanoseconds
Thread.sleep(forTimeInterval: seconds)
let after = sample()
let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9

print("group\tprocesses\tcpu%\tidle_wakeups/s\tinterrupt_wakeups/s\tenergy_mW\tfootprint_MB")
for (index, (label, _)) in groups.enumerated() {
    let a = before[index], b = after[index]
    let cpu = Double(b.cpu &- a.cpu) * toNanoseconds / 1e9 / elapsed * 100
    let idle = Double(b.idle &- a.idle) / elapsed
    let interrupt = Double(b.interrupt &- a.interrupt) / elapsed
    let energy = Double(b.energy &- a.energy) / elapsed / 1e6
    let footprint = Double(b.footprint) / 1_048_576
    print(
        String(
            format: "%@\t%d\t%.2f\t%.1f\t%.1f\t%.1f\t%.1f", label, b.alive, cpu, idle, interrupt, energy, footprint))
}
