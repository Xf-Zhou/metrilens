import Foundation

private enum MetricFailureSource: Hashable {
    case cpu
    case memory
    case batteryTemperature
    case batteryStatus
    case network
    case disk
}

struct MetricHistorySeries {
    static let chartWindow: TimeInterval = 10 * 60
    static let summaryWindow: TimeInterval = 60
    private static let minimumSamplePeriod =
        AppPreferences.allowedRefreshIntervals.min() ?? 1

    private var chart = MetricHistoryBuffer(
        window: chartWindow,
        capacity: Int(chartWindow / minimumSamplePeriod) + 1
    )
    private var summary = MetricHistoryBuffer(
        window: summaryWindow,
        capacity: Int(summaryWindow / minimumSamplePeriod) + 1
    )

    mutating func append(percent: Double, at uptime: TimeInterval) {
        chart.append(percent: percent, at: uptime)
        summary.append(percent: percent, at: uptime)
    }

    mutating func values(now: TimeInterval) -> [MetricHistoryPoint] {
        chart.values(now: now)
    }

    mutating func recentSummary(now: TimeInterval) -> MetricHistorySummary? {
        summary.summary(now: now)
    }

    func isCollecting(now: TimeInterval) -> Bool {
        chart.isCollecting(now: now)
    }

    mutating func clear() {
        chart.clear()
        summary.clear()
    }
}

final class MetricSampler {
    private let queue = DispatchQueue(label: "com.xfzhou.Metrilens.sampler", qos: .utility)
    private let cpuProvider: CPUProviding
    private let memoryProvider: MemoryProviding
    private let batteryProvider: BatteryTemperatureProviding
    private let batteryStatusProvider: BatteryStatusProviding
    private let networkProvider: NetworkProviding
    private let diskProvider: DiskCapacityProviding
    private let thermalProvider: ThermalStateProviding
    private let uptimeProvider: () -> TimeInterval
    private let lowPowerProvider: () -> Bool
    private let wallTimeProvider: () -> Date
    private lazy var scheduler = ProviderDeadlineScheduler(queue: queue) { [weak self] due in
        self?.sample(due)
    }

    private var snapshot = SystemSnapshot.initial()
    private var cpuHistory = MetricHistorySeries()
    private var memoryHistory = MetricHistorySeries()
    private var preferences: PreferencesSnapshot
    private var popoverVisible = false
    private var sleeping = false
    private var isRunning = false
    private var lastPeriods: [ProviderID: TimeInterval] = [:]
    private var systemEventCoalescer = SystemEventCoalescer()
    private var batterySessionMaximum: (value: Double, stamp: SampleStamp)?
    private var lastFailures: [MetricFailureSource: MetricFailure] = [:]

    var onSnapshot: ((SystemSnapshot) -> Void)?

    init(
        preferences: PreferencesSnapshot,
        cpuProvider: CPUProviding = CPUProvider(),
        memoryProvider: MemoryProviding = MemoryProvider(),
        batteryProvider: BatteryTemperatureProviding = BatteryTemperatureProvider(),
        batteryStatusProvider: BatteryStatusProviding = BatteryStatusProvider(),
        networkProvider: NetworkProviding = NetworkProvider(),
        diskProvider: DiskCapacityProviding = DiskCapacityProvider(),
        thermalProvider: ThermalStateProviding = ThermalStateProvider(),
        uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        lowPowerProvider: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        wallTimeProvider: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.cpuProvider = cpuProvider
        self.memoryProvider = memoryProvider
        self.batteryProvider = batteryProvider
        self.batteryStatusProvider = batteryStatusProvider
        self.networkProvider = networkProvider
        self.diskProvider = diskProvider
        self.thermalProvider = thermalProvider
        self.uptimeProvider = uptimeProvider
        self.lowPowerProvider = lowPowerProvider
        self.wallTimeProvider = wallTimeProvider
    }

    func start() {
        queue.async {
            self.isRunning = true
            self.snapshot.thermalLevel = self.thermalProvider.current()
            self.snapshot.batteryMaximumTemperature = self.batteryProvider.sampleMaximum()
            self.recordFailure(
                self.batteryProvider.lastMaximumSampleFailure,
                provider: .battery,
                source: .batteryTemperature
            )
            self.snapshot.batteryTemperature = self.batteryProvider.currentTemperature
            self.snapshot.battery = self.batteryStatusProvider.state
            self.snapshot.network = self.networkProvider.state
            self.snapshot.disk = self.diskProvider.state
            self.synchronizeBatterySessionMaximum()
            self.reconfigure(force: Set(self.effectivePeriods().keys))
            self.publish()
        }
    }

    func stop() {
        queue.sync {
            scheduler.stop()
            batteryProvider.pause(nowUptime: uptimeProvider())
            batteryStatusProvider.pause(nowUptime: uptimeProvider())
            networkProvider.pause(nowUptime: uptimeProvider())
            diskProvider.pause(nowUptime: uptimeProvider())
            isRunning = false
            lastPeriods = [:]
            updateRuntimeState()
        }
    }

    func updatePreferences(_ preferences: PreferencesSnapshot) {
        queue.async {
            self.preferences = preferences
            self.reconfigure()
            self.publish()
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        queue.async {
            self.popoverVisible = visible
            self.reconfigure()
            self.publish()
        }
    }

    func systemWillSleep() {
        queue.async {
            self.sleeping = true
            self.cpuProvider.resetBaseline()
            self.networkProvider.resetBaseline()
            self.reconfigure()
            self.publish()
        }
    }

    func systemDidWake() {
        queue.async {
            let wasSleeping = self.sleeping
            self.sleeping = false
            self.cpuProvider.resetBaseline()
            self.networkProvider.resetBaseline()
            self.batteryProvider.resetCapabilities()
            self.batteryStatusProvider.resetCapabilities()
            self.snapshot.battery = self.batteryStatusProvider.state
            self.snapshot.batteryTemperature = self.batteryProvider.currentTemperature
            if wasSleeping {
                let shouldRefreshMaximum = self.systemEventCoalescer.shouldAccept(
                    at: self.uptimeProvider()
                )
                if shouldRefreshMaximum {
                    self.snapshot.batteryMaximumTemperature = self.batteryProvider.sampleMaximum()
                    self.recordFailure(
                        self.batteryProvider.lastMaximumSampleFailure,
                        provider: .battery,
                        source: .batteryTemperature
                    )
                    self.snapshot.batteryTemperature = self.batteryProvider.currentTemperature
                    self.synchronizeBatterySessionMaximum()
                }
                self.reconfigure(force: Set(self.effectivePeriods().keys))
                self.publish()
            } else {
                self.forceRefreshAfterSystemEvent(refreshMaximum: true)
            }
        }
    }

    func powerSourceChanged() {
        queue.async {
            guard !self.sleeping else { return }
            self.forceRefreshAfterSystemEvent(providers: [.battery], refreshMaximum: true)
        }
    }

    func powerStateChanged() {
        queue.async {
            self.reconfigure()
            self.publish()
        }
    }

    func thermalStateChanged() {
        queue.async {
            self.snapshot.thermalLevel = self.thermalProvider.current()
            self.publish()
        }
    }

    func resetBatterySessionMaximum() {
        queue.async {
            guard self.snapshot.batteryTemperature.freshValue != nil else {
                return
            }
            self.batterySessionMaximum = nil
            self.synchronizeBatterySessionMaximum(resetToCurrent: true)
            self.publish()
        }
    }

    func waitUntilIdleForTesting() {
        queue.sync {}
    }

    func debugStateForTesting() -> (SystemSnapshot, SchedulerDebugState) {
        queue.sync {
            (snapshot, scheduler.debugState())
        }
    }

    func effectiveCPUPeriodForDiagnostics() -> TimeInterval? {
        queue.sync {
            lastPeriods[.cpu]
        }
    }

    private func sample(_ due: Set<ProviderID>) {
        dispatchPrecondition(condition: .onQueue(queue))
        let periods = effectivePeriods()
        var shouldReconfigureBattery = false
        for provider in due {
            guard let period = periods[provider] else {
                scheduler.complete(provider)
                continue
            }
            switch provider {
            case .cpu:
                snapshot.cpu = cpuProvider.sample(period: period)
                if case let .available(metric, stamp) = snapshot.cpu {
                    cpuHistory.append(percent: metric.percent, at: stamp.uptime)
                }
                recordFailure(
                    cpuProvider.lastSampleFailure,
                    provider: .cpu,
                    source: .cpu
                )
            case .memory:
                snapshot.memory = memoryProvider.sample(period: period)
                if case let .available(metric, stamp) = snapshot.memory {
                    memoryHistory.append(percent: metric.percent, at: stamp.uptime)
                }
                recordFailure(
                    memoryProvider.lastSampleFailure,
                    provider: .memory,
                    source: .memory
                )
            case .battery:
                let sampledTemperature =
                    batteryProvider.shouldScheduleRoutineCurrentSample
                if sampledTemperature {
                    snapshot.batteryTemperature =
                        batteryProvider.sampleCurrent(period: period)
                    recordFailure(
                        batteryProvider.lastCurrentSampleFailure,
                        provider: .battery,
                        source: .batteryTemperature
                    )
                }
                snapshot.battery = batteryStatusProvider.sample(period: period)
                synchronizeBatterySessionMaximum()
                recordFailure(
                    batteryStatusProvider.lastSampleFailure,
                    provider: .battery,
                    source: .batteryStatus
                )
                shouldReconfigureBattery = batteryHardwareAbsent
            case .network:
                snapshot.network = networkProvider.sample(period: period)
                recordFailure(
                    networkProvider.lastSampleFailure,
                    provider: .network,
                    source: .network
                )
            case .disk:
                snapshot.disk = diskProvider.sample(period: period)
                recordFailure(
                    diskProvider.lastSampleFailure,
                    provider: .disk,
                    source: .disk
                )
            }
            scheduler.complete(provider)
        }
        if shouldReconfigureBattery {
            reconfigure()
        }
        let now = uptimeProvider()
        updateHistories(now: now)
        publish()
    }

    private func reconfigure(force: Set<ProviderID> = []) {
        dispatchPrecondition(condition: .onQueue(queue))
        let periods = effectivePeriods()
        let now = uptimeProvider()
        if lastPeriods[.cpu] != nil, periods[.cpu] == nil {
            cpuProvider.pause(nowUptime: now)
            snapshot.cpu = cpuProvider.state
            cpuHistory.clear()
            snapshot.cpuHistory = []
            snapshot.cpuHistoryCollecting = true
            snapshot.cpuHistorySummary = nil
        }
        if lastPeriods[.memory] != nil, periods[.memory] == nil {
            memoryProvider.pause(nowUptime: now)
            snapshot.memory = memoryProvider.state
            memoryHistory.clear()
            snapshot.memoryHistory = []
            snapshot.memoryHistoryCollecting = true
            snapshot.memoryHistorySummary = nil
        }
        if lastPeriods[.cpu] == nil, periods[.cpu] != nil {
            cpuProvider.expireCachedValue(nowUptime: now)
            snapshot.cpu = cpuProvider.state
            cpuProvider.resetBaseline()
        }
        if lastPeriods[.memory] == nil, periods[.memory] != nil {
            memoryProvider.expireCachedValue(nowUptime: now)
            snapshot.memory = memoryProvider.state
        }
        if let oldPeriod = lastPeriods[.cpu],
           let newPeriod = periods[.cpu],
           oldPeriod != newPeriod {
            cpuHistory.clear()
            snapshot.cpuHistory = []
            snapshot.cpuHistoryCollecting = true
            snapshot.cpuHistorySummary = nil
        }
        if let oldPeriod = lastPeriods[.memory],
           let newPeriod = periods[.memory],
           oldPeriod != newPeriod {
            memoryHistory.clear()
            snapshot.memoryHistory = []
            snapshot.memoryHistoryCollecting = true
            snapshot.memoryHistorySummary = nil
        }
        if lastPeriods[.battery] != nil, periods[.battery] == nil {
            batteryProvider.pause(nowUptime: now)
            batteryStatusProvider.pause(nowUptime: now)
            snapshot.batteryTemperature = batteryProvider.currentTemperature
            snapshot.battery = batteryStatusProvider.state
        }
        if lastPeriods[.battery] == nil, periods[.battery] != nil {
            batteryStatusProvider.expireCachedValue(nowUptime: now)
            snapshot.battery = batteryStatusProvider.state
        }
        if lastPeriods[.network] != nil, periods[.network] == nil {
            networkProvider.pause(nowUptime: now)
            snapshot.network = networkProvider.state
        }
        if lastPeriods[.network] == nil, periods[.network] != nil {
            networkProvider.expireCachedValue(nowUptime: now)
            networkProvider.resetBaseline()
            snapshot.network = networkProvider.state
        }
        if lastPeriods[.disk] != nil, periods[.disk] == nil {
            diskProvider.pause(nowUptime: now)
            snapshot.disk = diskProvider.state
        }
        if lastPeriods[.disk] == nil, periods[.disk] != nil {
            diskProvider.expireCachedValue(nowUptime: now)
            snapshot.disk = diskProvider.state
        }
        lastPeriods = periods
        updateRuntimeState()
        scheduler.update(periods: periods, force: force.intersection(periods.keys))
    }

    private func effectivePeriods() -> [ProviderID: TimeInterval] {
        var periods = SamplingPolicy.resolve(
            preferences: preferences,
            popoverVisible: popoverVisible,
            lowPower: lowPowerProvider(),
            sleeping: sleeping
        )
        if batteryHardwareAbsent {
            periods.removeValue(forKey: .battery)
        }
        return periods
    }

    private var batteryHardwareAbsent: Bool {
        guard case .unsupported(.noHardware) =
            batteryProvider.currentTemperature,
            case .unsupported(.noHardware) = batteryStatusProvider.state else {
            return false
        }
        return true
    }

    private func forceRefreshAfterSystemEvent(
        providers: Set<ProviderID>? = nil,
        refreshMaximum: Bool = false
    ) {
        let now = uptimeProvider()
        guard systemEventCoalescer.shouldAccept(at: now) else {
            return
        }
        let requested = providers ?? Set(effectivePeriods().keys)
        if refreshMaximum {
            snapshot.batteryMaximumTemperature = batteryProvider.sampleMaximum()
            recordFailure(
                batteryProvider.lastMaximumSampleFailure,
                provider: .battery,
                source: .batteryTemperature
            )
            snapshot.batteryTemperature = batteryProvider.currentTemperature
            if let period = effectivePeriods()[.battery] {
                snapshot.battery = batteryStatusProvider.sample(period: period)
                recordFailure(
                    batteryStatusProvider.lastSampleFailure,
                    provider: .battery,
                    source: .batteryStatus
                )
            }
            synchronizeBatterySessionMaximum()
        }
        reconfigure(force: requested)
        publish()
    }

    private func publish() {
        batteryProvider.expireMaximumIfNeeded(nowUptime: uptimeProvider())
        snapshot.batteryMaximumTemperature = batteryProvider.maximumTemperature
        updateHistories(now: uptimeProvider())
        updateRuntimeState()
        let value = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(value)
        }
    }

    private func updateHistories(now: TimeInterval) {
        snapshot.cpuHistory = cpuHistory.values(now: now)
        snapshot.cpuHistoryCollecting = cpuHistory.isCollecting(now: now)
        snapshot.cpuHistorySummary = cpuHistory.recentSummary(now: now)
        snapshot.memoryHistory = memoryHistory.values(now: now)
        snapshot.memoryHistoryCollecting = memoryHistory.isCollecting(now: now)
        snapshot.memoryHistorySummary = memoryHistory.recentSummary(now: now)
    }

    private func updateRuntimeState() {
        snapshot.samplingRuntime = SamplingRuntimeState(
            isRunning: isRunning,
            isSleeping: sleeping,
            isPopoverVisible: popoverVisible,
            effectivePeriods: lastPeriods
        )
    }

    private func synchronizeBatterySessionMaximum(resetToCurrent: Bool = false) {
        switch snapshot.batteryTemperature {
        case let .available(value, stamp):
            if resetToCurrent
                || batterySessionMaximum == nil
                || value > (batterySessionMaximum?.value ?? value) {
                batterySessionMaximum = (value, stamp)
            }
            if let batterySessionMaximum {
                snapshot.batterySessionMaximumTemperature = .available(
                    batterySessionMaximum.value,
                    batterySessionMaximum.stamp
                )
            }
        case let .unsupported(failure):
            if failure == .noHardware {
                batterySessionMaximum = nil
                snapshot.batterySessionMaximumTemperature = .unsupported(failure)
            } else if batterySessionMaximum == nil {
                snapshot.batterySessionMaximumTemperature = .unsupported(failure)
            }
        case let .unavailable(failure):
            if batterySessionMaximum == nil {
                snapshot.batterySessionMaximumTemperature = .unavailable(failure)
            }
        case .stale:
            break
        }
    }

    private func recordFailure(
        _ failure: MetricFailure?,
        provider: ProviderID,
        source: MetricFailureSource
    ) {
        guard let failure else {
            lastFailures.removeValue(forKey: source)
            return
        }
        guard lastFailures[source] != failure else { return }
        lastFailures[source] = failure
        snapshot.recentErrors.append(
            RecentMetricError(
                provider: provider,
                failure: failure,
                wallTime: wallTimeProvider()
            )
        )
        if snapshot.recentErrors.count > 5 {
            snapshot.recentErrors.removeFirst(snapshot.recentErrors.count - 5)
        }
    }
}
