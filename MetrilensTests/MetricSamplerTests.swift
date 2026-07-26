import XCTest
@testable import Metrilens

final class MetricSamplerTests: XCTestCase {
    func testUnsupportedBatteryIsRemovedFromRoutineDeadlines() {
        let battery = FakeBatteryProvider()
        battery.becomesUnsupportedOnFirstCurrentSample = true
        let sampled = expectation(description: "battery capability probe")
        battery.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(primaryMetric: .battery, battery: battery)

        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        let (_, scheduler) = sampler.debugStateForTesting()
        XCTAssertFalse(scheduler.scheduledProviders.contains(.battery))
        XCTAssertEqual(battery.currentSampleCount, 1)
        sampler.stop()
    }

    func testNoBatteryDetectedByMaximumProbeUpdatesBothStartupStates() {
        let battery = FakeBatteryProvider()
        battery.maximumReportsNoHardware = true
        let sampler = makeSampler(primaryMetric: .battery, battery: battery)

        sampler.start()
        sampler.waitUntilIdleForTesting()

        let (snapshot, scheduler) = sampler.debugStateForTesting()
        guard case .unsupported(.noHardware) = snapshot.batteryTemperature,
              case .unsupported(.noHardware) = snapshot.batteryMaximumTemperature else {
            return XCTFail("Both battery rows must agree that hardware is absent")
        }
        XCTAssertFalse(scheduler.scheduledProviders.contains(.battery))
        sampler.stop()
    }

    func testNoBatteryDetectedByWakeMaximumProbeUpdatesBothStates() {
        var uptime: TimeInterval = 100
        let battery = FakeBatteryProvider()
        let sampler = makeSampler(
            primaryMetric: .battery,
            battery: battery,
            uptimeProvider: { uptime }
        )
        sampler.start()
        sampler.waitUntilIdleForTesting()
        sampler.systemWillSleep()
        sampler.waitUntilIdleForTesting()

        battery.maximumReportsNoHardware = true
        uptime = 200
        sampler.systemDidWake()
        sampler.waitUntilIdleForTesting()

        let (snapshot, scheduler) = sampler.debugStateForTesting()
        guard case .unsupported(.noHardware) = snapshot.batteryTemperature,
              case .unsupported(.noHardware) = snapshot.batteryMaximumTemperature else {
            return XCTFail("Wake capability probe must synchronize both battery states")
        }
        XCTAssertFalse(scheduler.scheduledProviders.contains(.battery))
        sampler.stop()
    }

    func testUIPausePreservesFreshCPUCacheAndClearsHistoryBeforeResumeBaseline() {
        let cpu = FakeCPUProvider()
        let sampled = expectation(description: "initial CPU sample")
        cpu.onSample = { sampled.fulfill() }
        let battery = FakeBatteryProvider()
        let sampler = makeSampler(primaryMetric: .cpu, cpu: cpu, battery: battery)
        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        sampler.updatePreferences(preferences(.battery))
        sampler.waitUntilIdleForTesting()
        let (paused, _) = sampler.debugStateForTesting()
        guard case let .stale(metric, _) = paused.cpu else {
            return XCTFail("Paused CPU must preserve a fresh value as stale")
        }
        XCTAssertEqual(metric.percent, 20)
        XCTAssertTrue(paused.cpuHistory.isEmpty)
        XCTAssertTrue(paused.cpuHistoryCollecting)

        sampler.updatePreferences(preferences(.cpu))
        sampler.waitUntilIdleForTesting()
        let (resumed, _) = sampler.debugStateForTesting()
        guard case .stale = resumed.cpu else {
            return XCTFail("CPU must retain the cache while establishing a new baseline")
        }
        XCTAssertTrue(resumed.cpuHistoryCollecting)
        sampler.stop()
    }

    func testUIPausePreservesFreshMemoryCache() {
        let memory = FakeMemoryProvider()
        let sampled = expectation(description: "initial memory sample")
        memory.onSample = { sampled.fulfill() }
        let sampler = makeSampler(
            primaryMetric: .memory,
            memory: memory,
            battery: FakeBatteryProvider()
        )
        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        sampler.updatePreferences(preferences(.battery))
        sampler.waitUntilIdleForTesting()
        let (paused, _) = sampler.debugStateForTesting()
        guard case let .stale(metric, _) = paused.memory else {
            return XCTFail("Paused memory must preserve a fresh value as stale")
        }
        XCTAssertEqual(metric.percent, 50)
        sampler.stop()
    }

    func testWakeAndPowerSourceEventsShareTwoSecondCoalescingWindow() {
        var uptime: TimeInterval = 100
        let battery = FakeBatteryProvider()
        let sampler = makeSampler(
            primaryMetric: .battery,
            battery: battery,
            uptimeProvider: { uptime }
        )
        sampler.start()
        sampler.waitUntilIdleForTesting()
        XCTAssertEqual(battery.maximumSampleCount, 1)

        sampler.systemDidWake()
        sampler.waitUntilIdleForTesting()
        XCTAssertEqual(battery.maximumSampleCount, 2)

        uptime = 101
        sampler.powerSourceChanged()
        sampler.waitUntilIdleForTesting()
        XCTAssertEqual(battery.maximumSampleCount, 2)

        uptime = 102
        sampler.powerSourceChanged()
        sampler.waitUntilIdleForTesting()
        XCTAssertEqual(battery.maximumSampleCount, 3)
        sampler.stop()
    }

    func testPowerSourceBeforeWakeStillRestoresSamplingWithoutDuplicateMaximumRead() {
        var uptime: TimeInterval = 100
        let battery = FakeBatteryProvider()
        let cpu = FakeCPUProvider()
        let sampler = makeSampler(
            primaryMetric: .cpu,
            cpu: cpu,
            battery: battery,
            uptimeProvider: { uptime }
        )
        sampler.start()
        sampler.waitUntilIdleForTesting()
        sampler.systemWillSleep()
        sampler.waitUntilIdleForTesting()

        uptime = 200
        sampler.powerSourceChanged()
        sampler.waitUntilIdleForTesting()
        XCTAssertEqual(battery.maximumSampleCount, 1)

        uptime = 201
        sampler.systemDidWake()
        sampler.waitUntilIdleForTesting()
        let (_, scheduler) = sampler.debugStateForTesting()
        XCTAssertTrue(scheduler.scheduledProviders.contains(.cpu))
        XCTAssertEqual(battery.maximumSampleCount, 2)
        sampler.stop()
    }

    func testDiagnosticCPUPeriodComesFromEffectiveSchedulerConfiguration() {
        let sampler = MetricSampler(
            preferences: preferences(.cpu),
            cpuProvider: FakeCPUProvider(),
            memoryProvider: FakeMemoryProvider(),
            batteryProvider: FakeBatteryProvider(),
            thermalProvider: FakeThermalProvider(),
            lowPowerProvider: { true }
        )
        sampler.start()
        sampler.waitUntilIdleForTesting()
        XCTAssertEqual(sampler.effectiveCPUPeriodForDiagnostics(), 5)
        sampler.stop()
    }

    func testPopoverStormDoesNotResetActiveCPUBaselineOrMoveDeadlines() {
        let cpu = FakeCPUProvider()
        let battery = FakeBatteryProvider()
        let sampled = expectation(description: "initial CPU")
        cpu.onSample = { sampled.fulfill() }
        let sampler = makeSampler(primaryMetric: .cpu, cpu: cpu, battery: battery)
        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()
        let (_, before) = sampler.debugStateForTesting()

        for index in 0..<100 {
            sampler.setPopoverVisible(index.isMultiple(of: 2))
        }
        sampler.waitUntilIdleForTesting()
        let (_, after) = sampler.debugStateForTesting()

        XCTAssertEqual(cpu.resetCount, 1)
        XCTAssertEqual(after.lastRuns[.cpu], before.lastRuns[.cpu])
        XCTAssertEqual(after.deadlines[.cpu], before.deadlines[.cpu])
        sampler.stop()
    }

    func testRapidUIStateChangesDoNotBypassProviderCooldowns() {
        let cpu = FakeCPUProvider()
        let memory = FakeMemoryProvider()
        let battery = FakeBatteryProvider()
        let initialCPU = expectation(description: "initial CPU")
        cpu.onSample = { initialCPU.fulfill() }
        let sampler = MetricSampler(
            preferences: preferences(.cpu),
            cpuProvider: cpu,
            memoryProvider: memory,
            batteryProvider: battery,
            thermalProvider: FakeThermalProvider(),
            lowPowerProvider: { false }
        )
        sampler.start()
        wait(for: [initialCPU], timeout: 1)

        for index in 0..<100 {
            sampler.setPopoverVisible(index.isMultiple(of: 2))
            sampler.updatePreferences(preferences(PrimaryMetric.allCases[index % 3]))
        }
        sampler.waitUntilIdleForTesting()
        Thread.sleep(forTimeInterval: 0.05)
        sampler.waitUntilIdleForTesting()

        let (snapshot, scheduler) = sampler.debugStateForTesting()
        XCTAssertEqual(scheduler.activeTimerCount, 1)
        XCTAssertTrue(scheduler.inFlightProviders.isEmpty)
        XCTAssertLessThanOrEqual(cpu.sampleCount, 1)
        XCTAssertLessThanOrEqual(memory.sampleCount, 1)
        XCTAssertLessThanOrEqual(battery.currentSampleCount, 1)
        XCTAssertLessThanOrEqual(snapshot.cpuHistory.count, 1)
        XCTAssertLessThanOrEqual(cpu.maximumConcurrentSamples, 1)
        XCTAssertLessThanOrEqual(memory.maximumConcurrentSamples, 1)
        XCTAssertLessThanOrEqual(battery.maximumConcurrentSamples, 1)
        sampler.stop()
    }

    private func makeSampler(
        primaryMetric: PrimaryMetric,
        cpu: FakeCPUProvider = FakeCPUProvider(),
        memory: FakeMemoryProvider = FakeMemoryProvider(),
        battery: FakeBatteryProvider,
        uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> MetricSampler {
        MetricSampler(
            preferences: preferences(primaryMetric),
            cpuProvider: cpu,
            memoryProvider: memory,
            batteryProvider: battery,
            thermalProvider: FakeThermalProvider(),
            uptimeProvider: uptimeProvider,
            lowPowerProvider: { false }
        )
    }

    private func preferences(_ metric: PrimaryMetric) -> PreferencesSnapshot {
        PreferencesSnapshot(
            primaryMetric: metric,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true
        )
    }
}

private final class FakeCPUProvider: CPUProviding {
    var state: MetricState<CPUMetric> = .unavailable(.fieldMissing)
    var sampleCount = 0
    var resetCount = 0
    var pauseCount = 0
    var maximumConcurrentSamples = 0
    var onSample: (() -> Void)?
    private var concurrentSamples = 0

    func resetBaseline() {
        resetCount += 1
    }

    func pause(nowUptime: TimeInterval) {
        pauseCount += 1
        if case let .available(value, stamp) = state {
            state = .stale(value, stamp)
        }
    }

    func expireCachedValue(nowUptime: TimeInterval) {
        if case let .stale(_, stamp) = state,
           nowUptime - stamp.uptime >= 10 {
            state = .unavailable(.fieldMissing)
        }
    }

    func sample(period: TimeInterval) -> MetricState<CPUMetric> {
        concurrentSamples += 1
        maximumConcurrentSamples = max(maximumConcurrentSamples, concurrentSamples)
        sampleCount += 1
        state = .available(CPUMetric(percent: 20), .now())
        concurrentSamples -= 1
        onSample?()
        return state
    }
}

private final class FakeMemoryProvider: MemoryProviding {
    var state: MetricState<MemoryMetric> = .unavailable(.fieldMissing)
    var sampleCount = 0
    var maximumConcurrentSamples = 0
    var onSample: (() -> Void)?
    private var concurrentSamples = 0

    func pause(nowUptime: TimeInterval) {
        if case let .available(value, stamp) = state {
            state = .stale(value, stamp)
        }
    }

    func expireCachedValue(nowUptime: TimeInterval) {
        if case let .stale(_, stamp) = state,
           nowUptime - stamp.uptime >= 10 {
            state = .unavailable(.fieldMissing)
        }
    }

    func sample(period: TimeInterval) -> MetricState<MemoryMetric> {
        concurrentSamples += 1
        maximumConcurrentSamples = max(maximumConcurrentSamples, concurrentSamples)
        sampleCount += 1
        state = .available(
            MemoryMetric(usedBytes: 50, totalBytes: 100, availableBytes: 50, purgeableBytes: 0),
            .now()
        )
        concurrentSamples -= 1
        onSample?()
        return state
    }
}

private final class FakeBatteryProvider: BatteryTemperatureProviding {
    var currentTemperature: MetricState<Double> = .unavailable(.fieldMissing)
    var maximumTemperature: MetricState<Double> = .unavailable(.fieldMissing)
    var shouldScheduleRoutineCurrentSample = true
    var becomesUnsupportedOnFirstCurrentSample = false
    var maximumReportsNoHardware = false
    var currentSampleCount = 0
    var maximumSampleCount = 0
    var maximumConcurrentSamples = 0
    var onCurrentSample: (() -> Void)?
    private var concurrentSamples = 0

    func sampleCurrent(period: TimeInterval) -> MetricState<Double> {
        concurrentSamples += 1
        maximumConcurrentSamples = max(maximumConcurrentSamples, concurrentSamples)
        currentSampleCount += 1
        if becomesUnsupportedOnFirstCurrentSample {
            currentTemperature = .unsupported(.noHardware)
            shouldScheduleRoutineCurrentSample = false
        } else {
            currentTemperature = .available(35, .now())
        }
        concurrentSamples -= 1
        onCurrentSample?()
        return currentTemperature
    }

    func sampleMaximum() -> MetricState<Double> {
        maximumSampleCount += 1
        if maximumReportsNoHardware {
            currentTemperature = .unsupported(.noHardware)
            maximumTemperature = .unsupported(.noHardware)
            shouldScheduleRoutineCurrentSample = false
        } else {
            maximumTemperature = .available(40, .now())
        }
        return maximumTemperature
    }

    func pause() {}

    func resetCapabilities() {
        shouldScheduleRoutineCurrentSample = true
    }

    func expireMaximumIfNeeded(nowUptime: TimeInterval) {}
}

private struct FakeThermalProvider: ThermalStateProviding {
    func current() -> ThermalLevel { .nominal }
}
