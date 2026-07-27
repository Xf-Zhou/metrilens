import Foundation

enum PrimaryMetric: String, CaseIterable {
    case cpu
    case memory
    case battery
    case network
    case disk
}

enum StatusDisplayMode: String, CaseIterable {
    case single
    case compact
}

enum StatusSeparator: String, CaseIterable {
    case dot
    case bar
    case space

    var text: String {
        switch self {
        case .dot: return " · "
        case .bar: return " | "
        case .space: return "  "
        }
    }
}

struct PreferencesSnapshot: Equatable {
    let primaryMetric: PrimaryMetric
    let refreshInterval: TimeInterval
    let launchAtLogin: Bool
    let showsSparkline: Bool
    let statusDisplayMode: StatusDisplayMode
    let compactMetrics: [PrimaryMetric]
    let metricOrder: [PrimaryMetric]
    let statusSeparator: StatusSeparator
    let statusDecimalPlaces: Int
    let language: AppLanguage
    let alertsEnabled: Bool
    let cpuAlertEnabled: Bool
    let memoryAlertEnabled: Bool
    let thermalAlertEnabled: Bool
    let batteryLevelAlertEnabled: Bool
    let batteryTemperatureAlertEnabled: Bool
    let diskFreeAlertEnabled: Bool
    let cpuAlertThreshold: Double
    let memoryAlertThreshold: Double
    let batteryLevelAlertThreshold: Double
    let batteryTemperatureAlertThreshold: Double
    let diskFreeAlertThreshold: Double
    let alertSustainDuration: TimeInterval

    init(
        primaryMetric: PrimaryMetric,
        refreshInterval: TimeInterval,
        launchAtLogin: Bool,
        showsSparkline: Bool,
        statusDisplayMode: StatusDisplayMode = .single,
        compactMetrics: [PrimaryMetric] = [.cpu, .battery],
        metricOrder: [PrimaryMetric] = PrimaryMetric.allCases,
        statusSeparator: StatusSeparator = .dot,
        statusDecimalPlaces: Int = 0,
        language: AppLanguage = .system,
        alertsEnabled: Bool = false,
        cpuAlertEnabled: Bool = true,
        memoryAlertEnabled: Bool = true,
        thermalAlertEnabled: Bool = true,
        batteryLevelAlertEnabled: Bool = false,
        batteryTemperatureAlertEnabled: Bool = false,
        diskFreeAlertEnabled: Bool = false,
        cpuAlertThreshold: Double = 90,
        memoryAlertThreshold: Double = 90,
        batteryLevelAlertThreshold: Double = 20,
        batteryTemperatureAlertThreshold: Double = 45,
        diskFreeAlertThreshold: Double = 10,
        alertSustainDuration: TimeInterval = 30
    ) {
        self.primaryMetric = primaryMetric
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
        self.showsSparkline = showsSparkline
        self.statusDisplayMode = statusDisplayMode
        self.compactMetrics = Self.normalizedCompactMetrics(compactMetrics)
        self.metricOrder = Self.normalizedMetricOrder(metricOrder)
        self.statusSeparator = statusSeparator
        self.statusDecimalPlaces = statusDecimalPlaces
        self.language = language
        self.alertsEnabled = alertsEnabled
        self.cpuAlertEnabled = cpuAlertEnabled
        self.memoryAlertEnabled = memoryAlertEnabled
        self.thermalAlertEnabled = thermalAlertEnabled
        self.batteryLevelAlertEnabled = batteryLevelAlertEnabled
        self.batteryTemperatureAlertEnabled = batteryTemperatureAlertEnabled
        self.diskFreeAlertEnabled = diskFreeAlertEnabled
        self.cpuAlertThreshold = cpuAlertThreshold
        self.memoryAlertThreshold = memoryAlertThreshold
        self.batteryLevelAlertThreshold = batteryLevelAlertThreshold
        self.batteryTemperatureAlertThreshold = batteryTemperatureAlertThreshold
        self.diskFreeAlertThreshold = diskFreeAlertThreshold
        self.alertSustainDuration = alertSustainDuration
    }

    var displayedMetrics: [PrimaryMetric] {
        guard statusDisplayMode == .compact else { return [primaryMetric] }
        let selected = Set(compactMetrics)
        return metricOrder.filter(selected.contains)
    }

    private static func normalizedCompactMetrics(
        _ metrics: [PrimaryMetric]
    ) -> [PrimaryMetric] {
        let ordered = orderedUnique(metrics)
        return ordered.isEmpty ? [.cpu, .battery] : ordered
    }

    private static func normalizedMetricOrder(
        _ metrics: [PrimaryMetric]
    ) -> [PrimaryMetric] {
        let ordered = orderedUnique(metrics)
        return ordered + PrimaryMetric.allCases.filter { !ordered.contains($0) }
    }

    private static func orderedUnique(
        _ metrics: [PrimaryMetric]
    ) -> [PrimaryMetric] {
        var seen = Set<PrimaryMetric>()
        return metrics.filter { seen.insert($0).inserted }
    }
}

final class AppPreferences {
    static let allowedRefreshIntervals: [TimeInterval] = [1, 2, 5, 10, 30]
    static let allowedAlertThresholds: [Double] = [80, 90, 95]
    static let allowedBatteryLevelThresholds: [Double] = [10, 20, 30]
    static let allowedBatteryTemperatureThresholds: [Double] = [40, 45, 50]
    static let allowedDiskFreeThresholds: [Double] = [5, 10, 15]
    static let allowedAlertDurations: [TimeInterval] = [30, 60, 120]
    static let allowedStatusDecimalPlaces = [0, 1]

    private enum Key {
        static let primaryMetric = "primaryMetric"
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let showsSparkline = "showsSparkline"
        static let statusDisplayMode = "statusDisplayMode"
        static let compactMetrics = "compactMetrics"
        static let metricOrder = "metricOrder"
        static let statusSeparator = "statusSeparator"
        static let statusDecimalPlaces = "statusDecimalPlaces"
        static let language = "language"
        static let alertsEnabled = "alertsEnabled"
        static let cpuAlertEnabled = "cpuAlertEnabled"
        static let memoryAlertEnabled = "memoryAlertEnabled"
        static let thermalAlertEnabled = "thermalAlertEnabled"
        static let batteryLevelAlertEnabled = "batteryLevelAlertEnabled"
        static let batteryTemperatureAlertEnabled = "batteryTemperatureAlertEnabled"
        static let diskFreeAlertEnabled = "diskFreeAlertEnabled"
        static let cpuAlertThreshold = "cpuAlertThreshold"
        static let memoryAlertThreshold = "memoryAlertThreshold"
        static let batteryLevelAlertThreshold = "batteryLevelAlertThreshold"
        static let batteryTemperatureAlertThreshold = "batteryTemperatureAlertThreshold"
        static let diskFreeAlertThreshold = "diskFreeAlertThreshold"
        static let alertSustainDuration = "alertSustainDuration"
    }

    private let defaults: UserDefaults
    var onChange: ((PreferencesSnapshot) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        repairStoredValues()
        defaults.register(defaults: [
            Key.primaryMetric: PrimaryMetric.cpu.rawValue,
            Key.refreshInterval: 1.0,
            Key.launchAtLogin: false,
            Key.showsSparkline: true,
            Key.statusDisplayMode: StatusDisplayMode.single.rawValue,
            Key.compactMetrics: [PrimaryMetric.cpu.rawValue, PrimaryMetric.battery.rawValue],
            Key.metricOrder: PrimaryMetric.allCases.map(\.rawValue),
            Key.statusSeparator: StatusSeparator.dot.rawValue,
            Key.statusDecimalPlaces: 0,
            Key.language: AppLanguage.system.rawValue,
            Key.alertsEnabled: false,
            Key.cpuAlertEnabled: true,
            Key.memoryAlertEnabled: true,
            Key.thermalAlertEnabled: true,
            Key.batteryLevelAlertEnabled: false,
            Key.batteryTemperatureAlertEnabled: false,
            Key.diskFreeAlertEnabled: false,
            Key.cpuAlertThreshold: 90.0,
            Key.memoryAlertThreshold: 90.0,
            Key.batteryLevelAlertThreshold: 20.0,
            Key.batteryTemperatureAlertThreshold: 45.0,
            Key.diskFreeAlertThreshold: 10.0,
            Key.alertSustainDuration: 30.0
        ])
    }

    var snapshot: PreferencesSnapshot {
        if ProcessInfo.processInfo.environment["METRILENS_PERF_MODE"] == "1" {
            return PreferencesSnapshot(
                primaryMetric: .cpu,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: true,
                statusDisplayMode: .single,
                compactMetrics: [.cpu, .battery],
                language: .system,
                alertsEnabled: false
            )
        }
        let metric = PrimaryMetric(
            rawValue: defaults.string(forKey: Key.primaryMetric) ?? ""
        ) ?? .cpu
        let interval = Self.allowedRefreshIntervals.contains(
            defaults.double(forKey: Key.refreshInterval)
        )
            ? defaults.double(forKey: Key.refreshInterval)
            : 1.0
        let compactMetrics = (defaults.stringArray(forKey: Key.compactMetrics) ?? [])
            .compactMap(PrimaryMetric.init(rawValue:))
        let metricOrder = (defaults.stringArray(forKey: Key.metricOrder) ?? [])
            .compactMap(PrimaryMetric.init(rawValue:))
        return PreferencesSnapshot(
            primaryMetric: metric,
            refreshInterval: interval,
            launchAtLogin: defaults.bool(forKey: Key.launchAtLogin),
            showsSparkline: defaults.bool(forKey: Key.showsSparkline),
            statusDisplayMode: StatusDisplayMode(
                rawValue: defaults.string(forKey: Key.statusDisplayMode) ?? ""
            ) ?? .single,
            compactMetrics: compactMetrics,
            metricOrder: metricOrder,
            statusSeparator: StatusSeparator(
                rawValue: defaults.string(forKey: Key.statusSeparator) ?? ""
            ) ?? .dot,
            statusDecimalPlaces: defaults.integer(forKey: Key.statusDecimalPlaces),
            language: AppLanguage(
                rawValue: defaults.string(forKey: Key.language) ?? ""
            ) ?? .system,
            alertsEnabled: defaults.bool(forKey: Key.alertsEnabled),
            cpuAlertEnabled: defaults.bool(forKey: Key.cpuAlertEnabled),
            memoryAlertEnabled: defaults.bool(forKey: Key.memoryAlertEnabled),
            thermalAlertEnabled: defaults.bool(forKey: Key.thermalAlertEnabled),
            batteryLevelAlertEnabled: defaults.bool(forKey: Key.batteryLevelAlertEnabled),
            batteryTemperatureAlertEnabled:
                defaults.bool(forKey: Key.batteryTemperatureAlertEnabled),
            diskFreeAlertEnabled: defaults.bool(forKey: Key.diskFreeAlertEnabled),
            cpuAlertThreshold: defaults.double(forKey: Key.cpuAlertThreshold),
            memoryAlertThreshold: defaults.double(forKey: Key.memoryAlertThreshold),
            batteryLevelAlertThreshold:
                defaults.double(forKey: Key.batteryLevelAlertThreshold),
            batteryTemperatureAlertThreshold:
                defaults.double(forKey: Key.batteryTemperatureAlertThreshold),
            diskFreeAlertThreshold: defaults.double(forKey: Key.diskFreeAlertThreshold),
            alertSustainDuration: defaults.double(forKey: Key.alertSustainDuration)
        )
    }

    func setPrimaryMetric(_ metric: PrimaryMetric) {
        defaults.set(metric.rawValue, forKey: Key.primaryMetric)
        notify()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard Self.allowedRefreshIntervals.contains(interval) else { return }
        defaults.set(interval, forKey: Key.refreshInterval)
        notify()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.launchAtLogin)
        notify()
    }

    func setShowsSparkline(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.showsSparkline)
        notify()
    }

    func setStatusDisplayMode(_ mode: StatusDisplayMode) {
        defaults.set(mode.rawValue, forKey: Key.statusDisplayMode)
        notify()
    }

    func setCompactMetrics(_ metrics: [PrimaryMetric]) {
        var seen = Set<PrimaryMetric>()
        let normalized = metrics.filter { seen.insert($0).inserted }
        guard !normalized.isEmpty else { return }
        defaults.set(normalized.map(\.rawValue), forKey: Key.compactMetrics)
        notify()
    }

    func setMetricOrder(_ metrics: [PrimaryMetric]) {
        guard Set(metrics) == Set(PrimaryMetric.allCases),
              metrics.count == PrimaryMetric.allCases.count else { return }
        defaults.set(metrics.map(\.rawValue), forKey: Key.metricOrder)
        notify()
    }

    func setStatusSeparator(_ separator: StatusSeparator) {
        defaults.set(separator.rawValue, forKey: Key.statusSeparator)
        notify()
    }

    func setStatusDecimalPlaces(_ places: Int) {
        guard Self.allowedStatusDecimalPlaces.contains(places) else { return }
        defaults.set(places, forKey: Key.statusDecimalPlaces)
        notify()
    }

    func setLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Key.language)
        notify()
    }

    func setAlertsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.alertsEnabled)
        notify()
    }

    func setAlertEnabled(_ enabled: Bool, kind: MetricAlertKind) {
        let key: String
        switch kind {
        case .cpu: key = Key.cpuAlertEnabled
        case .memory: key = Key.memoryAlertEnabled
        case .thermal: key = Key.thermalAlertEnabled
        case .batteryLevel: key = Key.batteryLevelAlertEnabled
        case .batteryTemperature: key = Key.batteryTemperatureAlertEnabled
        case .diskFree: key = Key.diskFreeAlertEnabled
        }
        defaults.set(enabled, forKey: key)
        notify()
    }

    func setCPUAlertThreshold(_ threshold: Double) {
        guard Self.allowedAlertThresholds.contains(threshold) else { return }
        defaults.set(threshold, forKey: Key.cpuAlertThreshold)
        notify()
    }

    func setMemoryAlertThreshold(_ threshold: Double) {
        guard Self.allowedAlertThresholds.contains(threshold) else { return }
        defaults.set(threshold, forKey: Key.memoryAlertThreshold)
        notify()
    }

    func setBatteryLevelAlertThreshold(_ threshold: Double) {
        guard Self.allowedBatteryLevelThresholds.contains(threshold) else { return }
        defaults.set(threshold, forKey: Key.batteryLevelAlertThreshold)
        notify()
    }

    func setBatteryTemperatureAlertThreshold(_ threshold: Double) {
        guard Self.allowedBatteryTemperatureThresholds.contains(threshold) else { return }
        defaults.set(threshold, forKey: Key.batteryTemperatureAlertThreshold)
        notify()
    }

    func setDiskFreeAlertThreshold(_ threshold: Double) {
        guard Self.allowedDiskFreeThresholds.contains(threshold) else { return }
        defaults.set(threshold, forKey: Key.diskFreeAlertThreshold)
        notify()
    }

    func setAlertSustainDuration(_ duration: TimeInterval) {
        guard Self.allowedAlertDurations.contains(duration) else { return }
        defaults.set(duration, forKey: Key.alertSustainDuration)
        notify()
    }

    func resetToDefaults() {
        [
            Key.primaryMetric,
            Key.refreshInterval,
            Key.launchAtLogin,
            Key.showsSparkline,
            Key.statusDisplayMode,
            Key.compactMetrics,
            Key.metricOrder,
            Key.statusSeparator,
            Key.statusDecimalPlaces,
            Key.language,
            Key.alertsEnabled,
            Key.cpuAlertEnabled,
            Key.memoryAlertEnabled,
            Key.thermalAlertEnabled,
            Key.batteryLevelAlertEnabled,
            Key.batteryTemperatureAlertEnabled,
            Key.diskFreeAlertEnabled,
            Key.cpuAlertThreshold,
            Key.memoryAlertThreshold,
            Key.batteryLevelAlertThreshold,
            Key.batteryTemperatureAlertThreshold,
            Key.diskFreeAlertThreshold,
            Key.alertSustainDuration
        ].forEach(defaults.removeObject(forKey:))
        notify()
    }

    private func repairStoredValues() {
        if let rawMetric = defaults.object(forKey: Key.primaryMetric),
           (!(rawMetric is String)
                || PrimaryMetric(rawValue: rawMetric as? String ?? "") == nil) {
            defaults.removeObject(forKey: Key.primaryMetric)
        }

        if let rawInterval = defaults.object(forKey: Key.refreshInterval) {
            let number = rawInterval as? NSNumber
            let isBoolean = number.map {
                CFGetTypeID($0) == CFBooleanGetTypeID()
            } ?? false
            let interval = number?.doubleValue
            if isBoolean
                || interval?.isFinite != true
                || !Self.allowedRefreshIntervals.contains(interval ?? .nan) {
                defaults.removeObject(forKey: Key.refreshInterval)
            }
        }

        repairEnum(
            key: Key.statusDisplayMode,
            isValid: { StatusDisplayMode(rawValue: $0) != nil }
        )
        repairEnum(
            key: Key.language,
            isValid: { AppLanguage(rawValue: $0) != nil }
        )
        repairEnum(
            key: Key.statusSeparator,
            isValid: { StatusSeparator(rawValue: $0) != nil }
        )
        repairCompactMetrics()
        repairMetricOrder()
        repairInteger(
            key: Key.statusDecimalPlaces,
            allowed: Self.allowedStatusDecimalPlaces
        )
        repairNumber(
            key: Key.cpuAlertThreshold,
            allowed: Self.allowedAlertThresholds
        )
        repairNumber(
            key: Key.memoryAlertThreshold,
            allowed: Self.allowedAlertThresholds
        )
        repairNumber(
            key: Key.alertSustainDuration,
            allowed: Self.allowedAlertDurations
        )
        repairNumber(
            key: Key.batteryLevelAlertThreshold,
            allowed: Self.allowedBatteryLevelThresholds
        )
        repairNumber(
            key: Key.batteryTemperatureAlertThreshold,
            allowed: Self.allowedBatteryTemperatureThresholds
        )
        repairNumber(
            key: Key.diskFreeAlertThreshold,
            allowed: Self.allowedDiskFreeThresholds
        )

        for key in [
            Key.launchAtLogin,
            Key.showsSparkline,
            Key.alertsEnabled,
            Key.cpuAlertEnabled,
            Key.memoryAlertEnabled,
            Key.thermalAlertEnabled,
            Key.batteryLevelAlertEnabled,
            Key.batteryTemperatureAlertEnabled,
            Key.diskFreeAlertEnabled
        ] {
            guard let value = defaults.object(forKey: key) else { continue }
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else {
                defaults.removeObject(forKey: key)
                continue
            }
        }
    }

    private func repairEnum(key: String, isValid: (String) -> Bool) {
        guard let value = defaults.object(forKey: key) else { return }
        guard let rawValue = value as? String, isValid(rawValue) else {
            defaults.removeObject(forKey: key)
            return
        }
    }

    private func repairCompactMetrics() {
        guard let value = defaults.object(forKey: Key.compactMetrics) else { return }
        guard let rawValues = value as? [String],
              !rawValues.isEmpty,
              rawValues.count <= PrimaryMetric.allCases.count else {
            defaults.removeObject(forKey: Key.compactMetrics)
            return
        }
        let metrics = rawValues.compactMap(PrimaryMetric.init(rawValue:))
        guard metrics.count == rawValues.count,
              Set(metrics).count == metrics.count else {
            defaults.removeObject(forKey: Key.compactMetrics)
            return
        }
    }

    private func repairMetricOrder() {
        guard let value = defaults.object(forKey: Key.metricOrder) else { return }
        guard let rawValues = value as? [String],
              rawValues.count == PrimaryMetric.allCases.count else {
            defaults.removeObject(forKey: Key.metricOrder)
            return
        }
        let metrics = rawValues.compactMap(PrimaryMetric.init(rawValue:))
        guard metrics.count == rawValues.count,
              Set(metrics) == Set(PrimaryMetric.allCases) else {
            defaults.removeObject(forKey: Key.metricOrder)
            return
        }
    }

    private func repairNumber(key: String, allowed: [Double]) {
        guard let rawValue = defaults.object(forKey: key) else { return }
        guard let number = rawValue as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              allowed.contains(number.doubleValue) else {
            defaults.removeObject(forKey: key)
            return
        }
    }

    private func repairInteger(key: String, allowed: [Int]) {
        guard let rawValue = defaults.object(forKey: key) else { return }
        guard let number = rawValue as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue == Double(number.intValue),
              allowed.contains(number.intValue) else {
            defaults.removeObject(forKey: key)
            return
        }
    }

    private func notify() {
        onChange?(snapshot)
    }
}
