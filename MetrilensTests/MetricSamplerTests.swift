import XCTest
@testable import Metrilens

final class MetricSamplerTests: XCTestCase {
    func testUnsupportedTemperatureStillSchedulesBatteryStatus() {
        let battery = FakeBatteryProvider()
        battery.becomesUnsupportedOnFirstCurrentSample = true
        let sampled = expectation(description: "battery capability probe")
        battery.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(primaryMetric: .battery, battery: battery)

        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        let (_, scheduler) = sampler.debugStateForTesting()
        XCTAssertTrue(scheduler.scheduledProviders.contains(.battery))
        XCTAssertEqual(battery.currentSampleCount, 1)
        sampler.stop()
    }

    func testBatteryScheduleStopsOnlyWhenBothProvidersReportNoHardware() {
        let temperature = FakeBatteryProvider()
        temperature.becomesUnsupportedOnFirstCurrentSample = true
        let status = FakeBatteryStatusProvider()
        status.reportsNoHardware = true
        let sampled = expectation(description: "both battery providers sampled")
        temperature.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(
            primaryMetric: .battery,
            battery: temperature,
            batteryStatus: status
        )

        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        let (_, scheduler) = sampler.debugStateForTesting()
        XCTAssertFalse(scheduler.scheduledProviders.contains(.battery))
        sampler.stop()
    }

    func testBatteryStatusFailureIsRecordedAfterTemperatureCapabilityFailure() {
        let temperature = FakeBatteryProvider()
        temperature.routineUnsupportedFailure = .fieldMissing
        let status = FakeBatteryStatusProvider()
        let sampled = expectation(description: "temperature capability sampled")
        temperature.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(
            primaryMetric: .battery,
            battery: temperature,
            batteryStatus: status
        )

        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        status.nextSampleFailure = .iokitFailure(17)
        sampler.powerSourceChanged()
        sampler.waitUntilIdleForTesting()

        let (snapshot, _) = sampler.debugStateForTesting()
        XCTAssertTrue(
            snapshot.recentErrors.contains {
                $0.provider == .battery && $0.failure == .iokitFailure(17)
            }
        )
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
        XCTAssertTrue(scheduler.scheduledProviders.contains(.battery))
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
              case .unsupported(.noHardware) = snapshot.batteryMaximumTemperature,
              case .unsupported(.noHardware) = snapshot.batterySessionMaximumTemperature else {
            return XCTFail("Wake capability probe must synchronize all battery states")
        }
        XCTAssertTrue(scheduler.scheduledProviders.contains(.battery))
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

    func testRemovingBatteryDisplayMarksCurrentTemperatureStale() {
        let battery = FakeBatteryProvider()
        let sampled = expectation(description: "initial battery sample")
        battery.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(primaryMetric: .battery, battery: battery)
        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        sampler.updatePreferences(preferences(.cpu))
        sampler.waitUntilIdleForTesting()

        let (snapshot, scheduler) = sampler.debugStateForTesting()
        guard case let .stale(value, _) = snapshot.batteryTemperature else {
            return XCTFail("A paused battery reading must not remain fresh")
        }
        XCTAssertEqual(value, 35)
        XCTAssertFalse(scheduler.scheduledProviders.contains(.battery))
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

    func testChangingSamplePeriodRestartsCPUAndMemoryHistory() {
        let cpu = FakeCPUProvider()
        let memory = FakeMemoryProvider()
        let initialSamples = expectation(description: "initial samples")
        initialSamples.expectedFulfillmentCount = 2
        cpu.onSample = { initialSamples.fulfill() }
        memory.onSample = { initialSamples.fulfill() }
        let initialPreferences = PreferencesSnapshot(
            display: DisplaySettings(
                statusDisplayMode: .compact,
                compactMetrics: [.cpu, .memory]
            )
        )
        let sampler = MetricSampler(
            preferences: initialPreferences,
            cpuProvider: cpu,
            memoryProvider: memory,
            batteryProvider: FakeBatteryProvider(),
            thermalProvider: FakeThermalProvider(),
            lowPowerProvider: { false }
        )
        sampler.start()
        wait(for: [initialSamples], timeout: 1)
        sampler.waitUntilIdleForTesting()

        sampler.updatePreferences(
            PreferencesSnapshot(
                display: DisplaySettings(
                    statusDisplayMode: .compact,
                    compactMetrics: [.cpu, .memory]
                ),
                sampling: SamplingSettings(refreshInterval: 5)
            )
        )
        sampler.waitUntilIdleForTesting()

        let (snapshot, _) = sampler.debugStateForTesting()
        XCTAssertTrue(snapshot.cpuHistory.isEmpty)
        XCTAssertTrue(snapshot.memoryHistory.isEmpty)
        XCTAssertNil(snapshot.cpuHistorySummary)
        XCTAssertNil(snapshot.memoryHistorySummary)
        XCTAssertTrue(snapshot.cpuHistoryCollecting)
        XCTAssertTrue(snapshot.memoryHistoryCollecting)
        sampler.stop()
    }

    func testPowerAndSleepChangesPublishRuntimeStateImmediately() {
        var lowPower = false
        let sampler = MetricSampler(
            preferences: preferences(.battery),
            cpuProvider: FakeCPUProvider(),
            memoryProvider: FakeMemoryProvider(),
            batteryProvider: FakeBatteryProvider(),
            thermalProvider: FakeThermalProvider(),
            lowPowerProvider: { lowPower }
        )
        let lowPowerPublished = expectation(description: "low power period published")
        let sleepPublished = expectation(description: "sleep state published")
        sampler.onSnapshot = { snapshot in
            if snapshot.samplingRuntime.effectivePeriods[.battery] == 120 {
                lowPowerPublished.fulfill()
            }
            if snapshot.samplingRuntime.isSleeping,
               snapshot.samplingRuntime.effectivePeriods.isEmpty {
                sleepPublished.fulfill()
            }
        }
        sampler.start()
        sampler.waitUntilIdleForTesting()

        lowPower = true
        sampler.powerStateChanged()
        wait(for: [lowPowerPublished], timeout: 1)

        sampler.systemWillSleep()
        wait(for: [sleepPublished], timeout: 1)
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

    func testBatterySessionMaximumCanResetToCurrentTemperature() {
        var uptime: TimeInterval = 100
        let battery = FakeBatteryProvider()
        battery.sampleTemperatures = [35, 42, 38]
        let sampled = expectation(description: "three battery samples")
        sampled.expectedFulfillmentCount = 3
        battery.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(
            primaryMetric: .battery,
            battery: battery,
            uptimeProvider: { uptime }
        )

        sampler.start()
        sampler.waitUntilIdleForTesting()
        uptime = 102
        sampler.powerSourceChanged()
        sampler.waitUntilIdleForTesting()
        uptime = 104
        sampler.powerSourceChanged()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        var (snapshot, _) = sampler.debugStateForTesting()
        XCTAssertEqual(snapshot.batteryTemperature.value, 38)
        XCTAssertEqual(snapshot.batterySessionMaximumTemperature.value, 42)

        sampler.resetBatterySessionMaximum()
        sampler.waitUntilIdleForTesting()
        (snapshot, _) = sampler.debugStateForTesting()
        XCTAssertEqual(snapshot.batterySessionMaximumTemperature.value, 38)
        sampler.stop()
    }

    func testNormalStartupDoesNotRecordSyntheticBatteryError() {
        let battery = FakeBatteryProvider()
        let sampled = expectation(description: "initial battery sample")
        battery.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(primaryMetric: .battery, battery: battery)

        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        let (snapshot, _) = sampler.debugStateForTesting()
        XCTAssertTrue(snapshot.recentErrors.isEmpty)
        XCTAssertTrue(snapshot.samplingRuntime.isRunning)
        XCTAssertEqual(snapshot.samplingRuntime.effectivePeriods[.battery], 30)
        sampler.stop()
    }

    func testStalePresentationStillRecordsActualCPUReadFailure() {
        let cpu = FakeCPUProvider()
        cpu.state = .available(CPUMetric(percent: 20), .now())
        cpu.nextSampleFailure = .machFailure(5)
        let sampled = expectation(description: "failed CPU sample")
        cpu.onSample = { sampled.fulfill() }
        let sampler = makeSampler(
            primaryMetric: .cpu,
            cpu: cpu,
            battery: FakeBatteryProvider()
        )

        sampler.start()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        let (snapshot, _) = sampler.debugStateForTesting()
        guard case .stale = snapshot.cpu else {
            return XCTFail("A cached CPU value should remain visibly stale")
        }
        XCTAssertEqual(snapshot.recentErrors.count, 1)
        XCTAssertEqual(snapshot.recentErrors.first?.provider, .cpu)
        XCTAssertEqual(snapshot.recentErrors.first?.failure, .machFailure(5))
        sampler.stop()
    }

    func testStaleBatteryTemperatureCannotResetSessionMaximum() {
        var uptime: TimeInterval = 100
        let battery = FakeBatteryProvider()
        battery.sampleTemperatures = [42, 38]
        battery.sampleFailuresAtCounts[3] = .iokitFailure(7)
        let sampled = expectation(description: "three battery samples")
        sampled.expectedFulfillmentCount = 3
        battery.onCurrentSample = { sampled.fulfill() }
        let sampler = makeSampler(
            primaryMetric: .battery,
            battery: battery,
            uptimeProvider: { uptime }
        )

        sampler.start()
        sampler.waitUntilIdleForTesting()
        uptime = 102
        sampler.powerSourceChanged()
        sampler.waitUntilIdleForTesting()
        uptime = 104
        sampler.powerSourceChanged()
        wait(for: [sampled], timeout: 1)
        sampler.waitUntilIdleForTesting()

        var (snapshot, _) = sampler.debugStateForTesting()
        guard case .stale = snapshot.batteryTemperature else {
            return XCTFail("Expected stale current temperature")
        }
        XCTAssertEqual(snapshot.batterySessionMaximumTemperature.value, 42)

        sampler.resetBatterySessionMaximum()
        sampler.waitUntilIdleForTesting()
        (snapshot, _) = sampler.debugStateForTesting()
        XCTAssertEqual(snapshot.batterySessionMaximumTemperature.value, 42)
        sampler.stop()
    }

    private func makeSampler(
        primaryMetric: PrimaryMetric,
        cpu: FakeCPUProvider = FakeCPUProvider(),
        memory: FakeMemoryProvider = FakeMemoryProvider(),
        battery: FakeBatteryProvider,
        batteryStatus: FakeBatteryStatusProvider = FakeBatteryStatusProvider(),
        network: FakeNetworkProvider = FakeNetworkProvider(),
        disk: FakeDiskProvider = FakeDiskProvider(),
        uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> MetricSampler {
        MetricSampler(
            preferences: preferences(primaryMetric),
            cpuProvider: cpu,
            memoryProvider: memory,
            batteryProvider: battery,
            batteryStatusProvider: batteryStatus,
            networkProvider: network,
            diskProvider: disk,
            thermalProvider: FakeThermalProvider(),
            uptimeProvider: uptimeProvider,
            lowPowerProvider: { false }
        )
    }

    private func preferences(_ metric: PrimaryMetric) -> PreferencesSnapshot {
        PreferencesSnapshot(
            display: DisplaySettings(primaryMetric: metric)
        )
    }
}

private final class FakeCPUProvider: CPUProviding {
    var state: MetricState<CPUMetric> = .unavailable(.fieldMissing)
    var lastSampleFailure: MetricFailure?
    var nextSampleFailure: MetricFailure?
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
        if let failure = nextSampleFailure {
            lastSampleFailure = failure
            nextSampleFailure = nil
            let stamp = state.stamp ?? .now()
            state = .stale(CPUMetric(percent: state.value?.percent ?? 20), stamp)
            concurrentSamples -= 1
            onSample?()
            return state
        }
        lastSampleFailure = nil
        state = .available(CPUMetric(percent: 20), .now())
        concurrentSamples -= 1
        onSample?()
        return state
    }
}

private final class FakeMemoryProvider: MemoryProviding {
    var state: MetricState<MemoryMetric> = .unavailable(.fieldMissing)
    var lastSampleFailure: MetricFailure?
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
        lastSampleFailure = nil
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
    var lastCurrentSampleFailure: MetricFailure?
    var lastMaximumSampleFailure: MetricFailure?
    var becomesUnsupportedOnFirstCurrentSample = false
    var routineUnsupportedFailure: MetricFailure?
    var maximumReportsNoHardware = false
    var currentSampleCount = 0
    var maximumSampleCount = 0
    var maximumConcurrentSamples = 0
    var sampleTemperatures: [Double] = []
    var sampleFailuresAtCounts: [Int: MetricFailure] = [:]
    var onCurrentSample: (() -> Void)?
    private var concurrentSamples = 0

    func sampleCurrent(period: TimeInterval) -> MetricState<Double> {
        concurrentSamples += 1
        maximumConcurrentSamples = max(maximumConcurrentSamples, concurrentSamples)
        currentSampleCount += 1
        lastCurrentSampleFailure = nil
        if let failure = sampleFailuresAtCounts[currentSampleCount] {
            lastCurrentSampleFailure = failure
            if let value = currentTemperature.value {
                currentTemperature = .stale(
                    value,
                    currentTemperature.stamp ?? .now()
                )
            } else {
                currentTemperature = .unavailable(failure)
            }
            concurrentSamples -= 1
            onCurrentSample?()
            return currentTemperature
        }
        if becomesUnsupportedOnFirstCurrentSample
            || routineUnsupportedFailure != nil {
            let failure = routineUnsupportedFailure ?? .noHardware
            lastCurrentSampleFailure = failure
            currentTemperature = .unsupported(failure)
            shouldScheduleRoutineCurrentSample = false
        } else {
            let temperature = sampleTemperatures.isEmpty
                ? 35
                : sampleTemperatures.removeFirst()
            currentTemperature = .available(temperature, .now())
        }
        concurrentSamples -= 1
        onCurrentSample?()
        return currentTemperature
    }

    func sampleMaximum() -> MetricState<Double> {
        maximumSampleCount += 1
        lastMaximumSampleFailure = nil
        if maximumReportsNoHardware {
            lastMaximumSampleFailure = .noHardware
            currentTemperature = .unsupported(.noHardware)
            maximumTemperature = .unsupported(.noHardware)
            shouldScheduleRoutineCurrentSample = false
        } else {
            maximumTemperature = .available(40, .now())
        }
        return maximumTemperature
    }

    func pause(nowUptime: TimeInterval) {
        if case let .available(value, stamp) = currentTemperature {
            currentTemperature = .stale(value, stamp)
        }
    }

    func resetCapabilities() {
        shouldScheduleRoutineCurrentSample = true
    }

    func expireMaximumIfNeeded(nowUptime: TimeInterval) {}
}

private final class FakeBatteryStatusProvider: BatteryStatusProviding {
    var state: MetricState<BatteryMetric> = .available(
        BatteryMetric(
            levelPercent: 80,
            powerState: .discharging,
            cycleCount: 100,
            health: .good,
            timeRemainingMinutes: 240
        ),
        .now()
    )
    var lastSampleFailure: MetricFailure?
    var reportsNoHardware = false
    var nextSampleFailure: MetricFailure?

    func sample(period: TimeInterval) -> MetricState<BatteryMetric> {
        if reportsNoHardware {
            lastSampleFailure = .noHardware
            state = .unsupported(.noHardware)
        } else if let failure = nextSampleFailure {
            nextSampleFailure = nil
            lastSampleFailure = failure
            if let value = state.value {
                state = .stale(value, state.stamp ?? .now())
            } else {
                state = .unavailable(failure)
            }
        } else {
            lastSampleFailure = nil
        }
        return state
    }

    func pause(nowUptime: TimeInterval) {
        if case let .available(value, stamp) = state {
            state = .stale(value, stamp)
        }
    }

    func expireCachedValue(nowUptime: TimeInterval) {}

    func resetCapabilities() {
        lastSampleFailure = nil
    }
}

private final class FakeNetworkProvider: NetworkProviding {
    var state: MetricState<NetworkMetric> = .unavailable(.noActiveInterface)
    var lastSampleFailure: MetricFailure?

    func sample(period: TimeInterval) -> MetricState<NetworkMetric> { state }
    func pause(nowUptime: TimeInterval) {}
    func resetBaseline() {}
    func expireCachedValue(nowUptime: TimeInterval) {}
}

private final class FakeDiskProvider: DiskCapacityProviding {
    var state: MetricState<DiskCapacityMetric> = .unavailable(.fieldMissing)
    var lastSampleFailure: MetricFailure?

    func sample(period: TimeInterval) -> MetricState<DiskCapacityMetric> { state }
    func pause(nowUptime: TimeInterval) {}
    func expireCachedValue(nowUptime: TimeInterval) {}
}

private struct FakeThermalProvider: ThermalStateProviding {
    func current() -> ThermalLevel { .nominal }
}
