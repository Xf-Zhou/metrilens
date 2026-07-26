import Foundation

enum PrimaryMetric: String, CaseIterable {
    case cpu
    case memory
    case battery
}

enum StatusDisplayMode: String, CaseIterable {
    case single
    case compact
}

struct PreferencesSnapshot: Equatable {
    let primaryMetric: PrimaryMetric
    let refreshInterval: TimeInterval
    let launchAtLogin: Bool
    let showsSparkline: Bool
    let statusDisplayMode: StatusDisplayMode
    let compactMetrics: [PrimaryMetric]
    let language: AppLanguage
    let alertsEnabled: Bool
    let cpuAlertThreshold: Double
    let memoryAlertThreshold: Double
    let alertSustainDuration: TimeInterval

    init(
        primaryMetric: PrimaryMetric,
        refreshInterval: TimeInterval,
        launchAtLogin: Bool,
        showsSparkline: Bool,
        statusDisplayMode: StatusDisplayMode = .single,
        compactMetrics: [PrimaryMetric] = [.cpu, .battery],
        language: AppLanguage = .system,
        alertsEnabled: Bool = false,
        cpuAlertThreshold: Double = 90,
        memoryAlertThreshold: Double = 90,
        alertSustainDuration: TimeInterval = 30
    ) {
        self.primaryMetric = primaryMetric
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
        self.showsSparkline = showsSparkline
        self.statusDisplayMode = statusDisplayMode
        self.compactMetrics = Self.normalizedCompactMetrics(compactMetrics)
        self.language = language
        self.alertsEnabled = alertsEnabled
        self.cpuAlertThreshold = cpuAlertThreshold
        self.memoryAlertThreshold = memoryAlertThreshold
        self.alertSustainDuration = alertSustainDuration
    }

    var displayedMetrics: [PrimaryMetric] {
        statusDisplayMode == .compact ? compactMetrics : [primaryMetric]
    }

    private static func normalizedCompactMetrics(
        _ metrics: [PrimaryMetric]
    ) -> [PrimaryMetric] {
        let selected = Set(metrics)
        let ordered = PrimaryMetric.allCases.filter(selected.contains)
        return ordered.isEmpty ? [.cpu, .battery] : ordered
    }
}

final class AppPreferences {
    static let allowedRefreshIntervals: [TimeInterval] = [1, 2, 5]
    static let allowedAlertThresholds: [Double] = [80, 90, 95]
    static let allowedAlertDurations: [TimeInterval] = [30, 60, 120]

    private enum Key {
        static let primaryMetric = "primaryMetric"
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let showsSparkline = "showsSparkline"
        static let statusDisplayMode = "statusDisplayMode"
        static let compactMetrics = "compactMetrics"
        static let language = "language"
        static let alertsEnabled = "alertsEnabled"
        static let cpuAlertThreshold = "cpuAlertThreshold"
        static let memoryAlertThreshold = "memoryAlertThreshold"
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
            Key.language: AppLanguage.system.rawValue,
            Key.alertsEnabled: false,
            Key.cpuAlertThreshold: 90.0,
            Key.memoryAlertThreshold: 90.0,
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
        return PreferencesSnapshot(
            primaryMetric: metric,
            refreshInterval: interval,
            launchAtLogin: defaults.bool(forKey: Key.launchAtLogin),
            showsSparkline: defaults.bool(forKey: Key.showsSparkline),
            statusDisplayMode: StatusDisplayMode(
                rawValue: defaults.string(forKey: Key.statusDisplayMode) ?? ""
            ) ?? .single,
            compactMetrics: compactMetrics,
            language: AppLanguage(
                rawValue: defaults.string(forKey: Key.language) ?? ""
            ) ?? .system,
            alertsEnabled: defaults.bool(forKey: Key.alertsEnabled),
            cpuAlertThreshold: defaults.double(forKey: Key.cpuAlertThreshold),
            memoryAlertThreshold: defaults.double(forKey: Key.memoryAlertThreshold),
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
        let selected = Set(metrics)
        let normalized = PrimaryMetric.allCases.filter(selected.contains)
        guard !normalized.isEmpty else { return }
        defaults.set(normalized.map(\.rawValue), forKey: Key.compactMetrics)
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
            Key.language,
            Key.alertsEnabled,
            Key.cpuAlertThreshold,
            Key.memoryAlertThreshold,
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
        repairCompactMetrics()
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

        for key in [Key.launchAtLogin, Key.showsSparkline, Key.alertsEnabled] {
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

    private func notify() {
        onChange?(snapshot)
    }
}
