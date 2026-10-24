import Exec
import Testing

struct ProcessCPUUsageTests {
    @Test func multithreadedProcessUsesMachineCapacity() throws {
        // 11.85 CPU seconds over three elapsed seconds reproduces the reported 395%.
        let percent = try #require(
            ProcessCPUUsage.percent(cpuTime: 11_850_000_000, elapsedTime: 3_000_000_000, processorCount: 8))
        #expect(percent == 49.375)
    }

    @Test(arguments: [1, 4, 8, 12])
    func oneBusyCoreUsesItsShare(processors: Int) {
        #expect(
            ProcessCPUUsage.percent(cpuTime: 3_000, elapsedTime: 3_000, processorCount: processors)
                == 100 / Double(processors))
    }

    @Test(arguments: [1, 4, 8, 12])
    func allBusyCoresUseOneHundredPercent(processors: Int) {
        #expect(
            ProcessCPUUsage.percent(cpuTime: UInt64(processors) * 3_000, elapsedTime: 3_000, processorCount: processors)
                == 100)
    }

    @Test func idleAndSmallReadingsKeepTheirPrecision() throws {
        #expect(ProcessCPUUsage.percent(cpuTime: 0, elapsedTime: 3_000, processorCount: 8) == 0)
        let percent = try #require(ProcessCPUUsage.percent(cpuTime: 24, elapsedTime: 3_000, processorCount: 8))
        #expect(abs(percent - 0.1) < 0.000_001)
    }

    @Test func unavailableCapacityCannotProduceAPercentage() {
        #expect(ProcessCPUUsage.percent(cpuTime: 1, elapsedTime: 0, processorCount: 8) == nil)
        #expect(ProcessCPUUsage.percent(cpuTime: 1, elapsedTime: 1, processorCount: 0) == nil)
        #expect(ProcessCPUUsage.percent(cpuTime: 1, elapsedTime: 1, processorCount: -1) == nil)
    }

    @Test func samplingSkewCannotExceedCapacity() {
        #expect(ProcessCPUUsage.percent(cpuTime: 24_001, elapsedTime: 3_000, processorCount: 8) == 100)
        #expect(ProcessCPUUsage.total([60, 40.001]) == 100)
    }

    @Test func largeCountersDoNotOverflow() {
        #expect(ProcessCPUUsage.percent(cpuTime: .max, elapsedTime: .max, processorCount: 8) == 12.5)
    }

    @Test func totalsDoNotNormalizeTwice() {
        let app = ProcessCPUUsage.total([0.5])
        let agent = ProcessCPUUsage.total([12.5, 25])
        let tools = ProcessCPUUsage.total([6.25])
        #expect(agent == 37.5)
        #expect(ProcessCPUUsage.total([agent, tools]) == 43.75)
        #expect(ProcessCPUUsage.total([app, agent, tools]) == 44.25)
        #expect(ProcessCPUUsage.total([]) == 0)
    }
}
