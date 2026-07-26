import Foundation

final class MetricSampler {
    private let queue = DispatchQueue(label: "com.xfzhou.Metrilens.sampler", qos: .utility)
    private let cpuProvider: CPUProviding
    private let memoryProvider: MemoryProviding
    private let batteryProvider: BatteryTemperatureProviding
    private let thermalProvider: ThermalStateProviding
    private let uptimeProvider: () -> TimeInterval
    private let lowPowerProvider: () -> Bool
    private lazy var scheduler = ProviderDeadlineScheduler(queue: queue) { [weak self] due in
        self?.sample(due)
    }

    private var snapshot = SystemSnapshot.initial()
    private var history = CPUHistoryBuffer()
    private var preferences: PreferencesSnapshot
    private var popoverVisible = false
    private var sleeping = false
    private var lastPeriods: [ProviderID: TimeInterval] = [:]
    private var systemEventCoalescer = SystemEventCoalescer()

    var onSnapshot: ((SystemSnapshot) -> Void)?

    init(
        preferences: PreferencesSnapshot,
        cpuProvider: CPUProviding = CPUProvider(),
        memoryProvider: MemoryProviding = MemoryProvider(),
        batteryProvider: BatteryTemperatureProviding = BatteryTemperatureProvider(),
        thermalProvider: ThermalStateProviding = ThermalStateProvider(),
        uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        lowPowerProvider: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.preferences = preferences
        self.cpuProvider = cpuProvider
        self.memoryProvider = memoryProvider
        self.batteryProvider = batteryProvider
        self.thermalProvider = thermalProvider
        self.uptimeProvider = uptimeProvider
        self.lowPowerProvider = lowPowerProvider
    }

    func start() {
        queue.async {
            self.snapshot.thermalLevel = self.thermalProvider.current()
            self.snapshot.batteryMaximumTemperature = self.batteryProvider.sampleMaximum()
            self.snapshot.batteryTemperature = self.batteryProvider.currentTemperature
            self.reconfigure(force: Set(self.effectivePeriods().keys))
            self.publish()
        }
    }

    func stop() {
        queue.sync {
            scheduler.stop()
            batteryProvider.pause()
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
            self.batteryProvider.pause()
            self.reconfigure()
        }
    }

    func systemDidWake() {
        queue.async {
            let wasSleeping = self.sleeping
            self.sleeping = false
            self.cpuProvider.resetBaseline()
            self.batteryProvider.resetCapabilities()
            self.snapshot.batteryTemperature = self.batteryProvider.currentTemperature
            if wasSleeping {
                let shouldRefreshMaximum = self.systemEventCoalescer.shouldAccept(
                    at: self.uptimeProvider()
                )
                if shouldRefreshMaximum {
                    self.snapshot.batteryMaximumTemperature = self.batteryProvider.sampleMaximum()
                    self.snapshot.batteryTemperature = self.batteryProvider.currentTemperature
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
        }
    }

    func thermalStateChanged() {
        queue.async {
            self.snapshot.thermalLevel = self.thermalProvider.current()
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
        var batteryCapabilityChanged = false
        for provider in due {
            guard let period = periods[provider] else {
                scheduler.complete(provider)
                continue
            }
            switch provider {
            case .cpu:
                snapshot.cpu = cpuProvider.sample(period: period)
                if case let .available(metric, stamp) = snapshot.cpu {
                    history.append(percent: metric.percent, at: stamp.uptime)
                }
            case .memory:
                snapshot.memory = memoryProvider.sample(period: period)
            case .battery:
                snapshot.batteryTemperature = batteryProvider.sampleCurrent(period: period)
                batteryCapabilityChanged = !batteryProvider.shouldScheduleRoutineCurrentSample
            }
            scheduler.complete(provider)
        }
        if batteryCapabilityChanged {
            reconfigure()
        }
        let now = uptimeProvider()
        snapshot.cpuHistory = history.values(now: now)
        snapshot.cpuHistoryCollecting = history.isCollecting(now: now)
        publish()
    }

    private func reconfigure(force: Set<ProviderID> = []) {
        dispatchPrecondition(condition: .onQueue(queue))
        let periods = effectivePeriods()
        let now = uptimeProvider()
        if lastPeriods[.cpu] != nil, periods[.cpu] == nil {
            cpuProvider.pause(nowUptime: now)
            snapshot.cpu = cpuProvider.state
            history.clear()
            snapshot.cpuHistory = []
            snapshot.cpuHistoryCollecting = true
        }
        if lastPeriods[.memory] != nil, periods[.memory] == nil {
            memoryProvider.pause(nowUptime: now)
            snapshot.memory = memoryProvider.state
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
        if lastPeriods[.battery] != nil, periods[.battery] == nil {
            batteryProvider.pause()
        }
        lastPeriods = periods
        scheduler.update(periods: periods, force: force.intersection(periods.keys))
    }

    private func effectivePeriods() -> [ProviderID: TimeInterval] {
        var periods = SamplingPolicy.resolve(
            preferences: preferences,
            popoverVisible: popoverVisible,
            lowPower: lowPowerProvider(),
            sleeping: sleeping
        )
        if !batteryProvider.shouldScheduleRoutineCurrentSample {
            periods.removeValue(forKey: .battery)
        }
        return periods
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
            snapshot.batteryTemperature = batteryProvider.currentTemperature
        }
        reconfigure(force: requested)
        publish()
    }

    private func publish() {
        batteryProvider.expireMaximumIfNeeded(nowUptime: uptimeProvider())
        snapshot.batteryMaximumTemperature = batteryProvider.maximumTemperature
        let value = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(value)
        }
    }
}
