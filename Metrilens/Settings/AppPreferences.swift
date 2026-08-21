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

enum NetworkStatusLayout: String, CaseIterable {
    case horizontal
    case vertical
}

enum InterfaceStyle: String, CaseIterable {
    case system
    case deepSea
    case engineAmber
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

struct DisplaySettings: Equatable {
    var primaryMetric: PrimaryMetric = .cpu
    var statusDisplayMode: StatusDisplayMode = .single
    var compactMetrics: [PrimaryMetric] = [.cpu, .battery]
    var metricOrder: [PrimaryMetric] = PrimaryMetric.allCases
    var statusSeparator: StatusSeparator = .dot
    var statusDecimalPlaces = 0
    var networkStatusLayout: NetworkStatusLayout = .vertical
    var language: AppLanguage = .system
    var interfaceStyle: InterfaceStyle = .system

    var displayedMetrics: [PrimaryMetric] {
        guard statusDisplayMode == .compact else { return [primaryMetric] }
        let selected = Set(compactMetrics)
        return metricOrder.filter(selected.contains)
    }

    var isValid: Bool {
        !compactMetrics.isEmpty
            && Set(compactMetrics).count == compactMetrics.count
            && Set(compactMetrics).isSubset(of: Set(PrimaryMetric.allCases))
            && metricOrder.count == PrimaryMetric.allCases.count
            && Set(metricOrder) == Set(PrimaryMetric.allCases)
            && AppPreferences.allowedStatusDecimalPlaces.contains(statusDecimalPlaces)
    }
}

struct SamplingSettings: Equatable {
    var refreshInterval: TimeInterval = 1
    var showsSparkline = true

    var isValid: Bool {
        AppPreferences.allowedRefreshIntervals.contains(refreshInterval)
    }
}

struct AlertThresholds: Equatable {
    var cpu = 90.0
    var memory = 90.0
    var batteryLevel = 20.0
    var batteryTemperature = 45.0
    var diskFree = 10.0
}

struct AlertSettings: Equatable {
    var enabled = false
    var enabledKinds: Set<MetricAlertKind> = [.cpu, .memory, .thermal]
    var thresholds = AlertThresholds()
    var sustainDuration: TimeInterval = 30

    func isEnabled(_ kind: MetricAlertKind) -> Bool {
        enabledKinds.contains(kind)
    }

    var isValid: Bool {
        enabledKinds.isSubset(of: Set(MetricAlertKind.allCases))
            && AppPreferences.allowedAlertThresholds.contains(thresholds.cpu)
            && AppPreferences.allowedAlertThresholds.contains(thresholds.memory)
            && AppPreferences.allowedBatteryLevelThresholds.contains(
                thresholds.batteryLevel
            )
            && AppPreferences.allowedBatteryTemperatureThresholds.contains(
                thresholds.batteryTemperature
            )
            && AppPreferences.allowedDiskFreeThresholds.contains(
                thresholds.diskFree
            )
            && AppPreferences.allowedAlertDurations.contains(sustainDuration)
    }
}

struct SystemSettings: Equatable {
    var launchAtLogin = false
}

struct PreferencesSnapshot: Equatable {
    var display = DisplaySettings()
    var sampling = SamplingSettings()
    var alerts = AlertSettings()
    var system = SystemSettings()

    var displayedMetrics: [PrimaryMetric] {
        display.displayedMetrics
    }

    static let standard = PreferencesSnapshot()
}

final class AppPreferences {
    static let allowedRefreshIntervals: [TimeInterval] = [0.5, 1, 2, 5, 10, 30]
    static let allowedAlertThresholds: [Double] = [80, 90, 95]
    static let allowedBatteryLevelThresholds: [Double] = [10, 20, 30]
    static let allowedBatteryTemperatureThresholds: [Double] = [40, 45, 50]
    static let allowedDiskFreeThresholds: [Double] = [5, 10, 15]
    static let allowedAlertDurations: [TimeInterval] = [30, 60, 120]
    static let allowedStatusDecimalPlaces = [0, 1]

    private let defaults: UserDefaults
    var onChange: ((PreferencesSnapshot) -> Void)?

    init(defaults: UserDefaults? = nil) {
        let store = defaults ?? Self.defaultStore()
        self.defaults = store
        SettingsSchema.repairStoredValues(in: store)
        store.register(defaults: SettingsSchema.registeredDefaults)
        if let language = Self.uiTestLanguage {
            SettingsSchema.Display.language.write(language, to: store)
        }
    }

    var snapshot: PreferencesSnapshot {
        if ProcessInfo.processInfo.environment["METRILENS_PERF_MODE"] == "1" {
            return .standard
        }
        return PreferencesSnapshot(
            display: DisplaySettings(
                primaryMetric: SettingsSchema.Display.primaryMetric.read(from: defaults),
                statusDisplayMode: SettingsSchema.Display.mode.read(from: defaults),
                compactMetrics: SettingsSchema.Display.compactMetrics.read(from: defaults),
                metricOrder: SettingsSchema.Display.metricOrder.read(from: defaults),
                statusSeparator: SettingsSchema.Display.separator.read(from: defaults),
                statusDecimalPlaces: SettingsSchema.Display.decimalPlaces.read(from: defaults),
                networkStatusLayout: SettingsSchema.Display.networkLayout.read(from: defaults),
                language: SettingsSchema.Display.language.read(from: defaults),
                interfaceStyle: SettingsSchema.Display.interfaceStyle.read(from: defaults)
            ),
            sampling: SamplingSettings(
                refreshInterval: SettingsSchema.Sampling.refreshInterval.read(from: defaults),
                showsSparkline: SettingsSchema.Sampling.showsSparkline.read(from: defaults)
            ),
            alerts: AlertSettings(
                enabled: SettingsSchema.Alerts.enabled.read(from: defaults),
                enabledKinds: Set(MetricAlertKind.allCases.filter {
                    SettingsSchema.Alerts.enabledSetting(for: $0).read(from: defaults)
                }),
                thresholds: AlertThresholds(
                    cpu: SettingsSchema.Alerts.cpuThreshold.read(from: defaults),
                    memory: SettingsSchema.Alerts.memoryThreshold.read(from: defaults),
                    batteryLevel: SettingsSchema.Alerts.batteryLevelThreshold.read(from: defaults),
                    batteryTemperature: SettingsSchema.Alerts.batteryTemperatureThreshold.read(from: defaults),
                    diskFree: SettingsSchema.Alerts.diskFreeThreshold.read(from: defaults)
                ),
                sustainDuration: SettingsSchema.Alerts.sustainDuration.read(from: defaults)
            ),
            system: SystemSettings(
                launchAtLogin: SettingsSchema.System.launchAtLogin.read(from: defaults)
            )
        )
    }

    func updateDisplay(_ update: (inout DisplaySettings) -> Void) {
        var value = snapshot.display
        update(&value)
        guard value.isValid else { return }
        SettingsSchema.Display.write(value, to: defaults)
        notify()
    }

    func updateSampling(_ update: (inout SamplingSettings) -> Void) {
        var value = snapshot.sampling
        update(&value)
        guard value.isValid else { return }
        SettingsSchema.Sampling.write(value, to: defaults)
        notify()
    }

    func updateAlerts(_ update: (inout AlertSettings) -> Void) {
        var value = snapshot.alerts
        update(&value)
        guard value.isValid else { return }
        SettingsSchema.Alerts.write(value, to: defaults)
        notify()
    }

    func updateSystem(_ update: (inout SystemSettings) -> Void) {
        var value = snapshot.system
        update(&value)
        SettingsSchema.System.write(value, to: defaults)
        notify()
    }

    func resetToDefaults() {
        SettingsSchema.reset(in: defaults)
        notify()
    }

    private func notify() {
        onChange?(snapshot)
    }

    private static func defaultStore() -> UserDefaults {
        let environment = ProcessInfo.processInfo.environment
        guard environment["METRILENS_UI_TESTING"] == "1" else {
            return .standard
        }
        let suiteName = "com.xfzhou.Metrilens.UITests"
        let store = UserDefaults(suiteName: suiteName)!
        if environment["METRILENS_UI_TEST_RESET"] == "1" {
            store.removePersistentDomain(forName: suiteName)
        }
        return store
    }

    private static var uiTestLanguage: AppLanguage? {
        guard ProcessInfo.processInfo.environment["METRILENS_UI_TESTING"] == "1",
              let rawValue = ProcessInfo.processInfo.environment[
                "METRILENS_UI_TEST_LANGUAGE"
              ] else {
            return nil
        }
        return AppLanguage(rawValue: rawValue)
    }
}

private struct StoredSetting<Value> {
    let key: String
    let defaultValue: Value
    let decode: (Any) -> Value?
    let encode: (Value) -> Any

    func read(from defaults: UserDefaults) -> Value {
        guard let rawValue = defaults.object(forKey: key) else {
            return defaultValue
        }
        return decode(rawValue) ?? defaultValue
    }

    func write(_ value: Value, to defaults: UserDefaults) {
        defaults.set(encode(value), forKey: key)
    }

    var definition: StoredSettingDefinition {
        StoredSettingDefinition(
            key: key,
            defaultValue: encode(defaultValue),
            isValid: { decode($0) != nil }
        )
    }
}

private struct StoredSettingDefinition {
    let key: String
    let defaultValue: Any
    let isValid: (Any) -> Bool
}

private enum SettingsSchema {
    enum Display {
        static let primaryMetric = enumSetting("primaryMetric", default: PrimaryMetric.cpu)
        static let mode = enumSetting("statusDisplayMode", default: StatusDisplayMode.single)
        static let compactMetrics = metricListSetting(
            "compactMetrics",
            default: [.cpu, .battery]
        ) { metrics in
            !metrics.isEmpty && Set(metrics).count == metrics.count
        }
        static let metricOrder = metricListSetting(
            "metricOrder",
            default: PrimaryMetric.allCases
        ) { metrics in
            metrics.count == PrimaryMetric.allCases.count
                && Set(metrics) == Set(PrimaryMetric.allCases)
        }
        static let separator = enumSetting("statusSeparator", default: StatusSeparator.dot)
        static let decimalPlaces = integerSetting(
            "statusDecimalPlaces",
            default: 0,
            allowed: AppPreferences.allowedStatusDecimalPlaces
        )
        static let networkLayout = enumSetting(
            "networkStatusLayout",
            default: NetworkStatusLayout.vertical
        )
        static let language = enumSetting("language", default: AppLanguage.system)
        static let interfaceStyle = enumSetting(
            "interfaceStyle",
            default: InterfaceStyle.system
        )

        static let definitions = [
            primaryMetric.definition,
            mode.definition,
            compactMetrics.definition,
            metricOrder.definition,
            separator.definition,
            decimalPlaces.definition,
            networkLayout.definition,
            language.definition,
            interfaceStyle.definition
        ]

        static func write(_ value: DisplaySettings, to defaults: UserDefaults) {
            primaryMetric.write(value.primaryMetric, to: defaults)
            mode.write(value.statusDisplayMode, to: defaults)
            compactMetrics.write(value.compactMetrics, to: defaults)
            metricOrder.write(value.metricOrder, to: defaults)
            separator.write(value.statusSeparator, to: defaults)
            decimalPlaces.write(value.statusDecimalPlaces, to: defaults)
            networkLayout.write(value.networkStatusLayout, to: defaults)
            language.write(value.language, to: defaults)
            interfaceStyle.write(value.interfaceStyle, to: defaults)
        }
    }

    enum Sampling {
        static let refreshInterval = doubleSetting(
            "refreshInterval",
            default: 1,
            allowed: AppPreferences.allowedRefreshIntervals
        )
        static let showsSparkline = booleanSetting("showsSparkline", default: true)
        static let definitions = [
            refreshInterval.definition,
            showsSparkline.definition
        ]

        static func write(_ value: SamplingSettings, to defaults: UserDefaults) {
            refreshInterval.write(value.refreshInterval, to: defaults)
            showsSparkline.write(value.showsSparkline, to: defaults)
        }
    }

    enum Alerts {
        static let enabled = booleanSetting("alertsEnabled", default: false)
        static let cpuEnabled = booleanSetting("cpuAlertEnabled", default: true)
        static let memoryEnabled = booleanSetting("memoryAlertEnabled", default: true)
        static let thermalEnabled = booleanSetting("thermalAlertEnabled", default: true)
        static let batteryLevelEnabled = booleanSetting(
            "batteryLevelAlertEnabled",
            default: false
        )
        static let batteryTemperatureEnabled = booleanSetting(
            "batteryTemperatureAlertEnabled",
            default: false
        )
        static let diskFreeEnabled = booleanSetting("diskFreeAlertEnabled", default: false)
        static let cpuThreshold = doubleSetting(
            "cpuAlertThreshold",
            default: 90,
            allowed: AppPreferences.allowedAlertThresholds
        )
        static let memoryThreshold = doubleSetting(
            "memoryAlertThreshold",
            default: 90,
            allowed: AppPreferences.allowedAlertThresholds
        )
        static let batteryLevelThreshold = doubleSetting(
            "batteryLevelAlertThreshold",
            default: 20,
            allowed: AppPreferences.allowedBatteryLevelThresholds
        )
        static let batteryTemperatureThreshold = doubleSetting(
            "batteryTemperatureAlertThreshold",
            default: 45,
            allowed: AppPreferences.allowedBatteryTemperatureThresholds
        )
        static let diskFreeThreshold = doubleSetting(
            "diskFreeAlertThreshold",
            default: 10,
            allowed: AppPreferences.allowedDiskFreeThresholds
        )
        static let sustainDuration = doubleSetting(
            "alertSustainDuration",
            default: 30,
            allowed: AppPreferences.allowedAlertDurations
        )

        static let definitions = [
            enabled.definition,
            cpuEnabled.definition,
            memoryEnabled.definition,
            thermalEnabled.definition,
            batteryLevelEnabled.definition,
            batteryTemperatureEnabled.definition,
            diskFreeEnabled.definition,
            cpuThreshold.definition,
            memoryThreshold.definition,
            batteryLevelThreshold.definition,
            batteryTemperatureThreshold.definition,
            diskFreeThreshold.definition,
            sustainDuration.definition
        ]

        static func enabledSetting(for kind: MetricAlertKind) -> StoredSetting<Bool> {
            switch kind {
            case .cpu: return cpuEnabled
            case .memory: return memoryEnabled
            case .thermal: return thermalEnabled
            case .batteryLevel: return batteryLevelEnabled
            case .batteryTemperature: return batteryTemperatureEnabled
            case .diskFree: return diskFreeEnabled
            }
        }

        static func write(_ value: AlertSettings, to defaults: UserDefaults) {
            enabled.write(value.enabled, to: defaults)
            for kind in MetricAlertKind.allCases {
                enabledSetting(for: kind).write(value.enabledKinds.contains(kind), to: defaults)
            }
            cpuThreshold.write(value.thresholds.cpu, to: defaults)
            memoryThreshold.write(value.thresholds.memory, to: defaults)
            batteryLevelThreshold.write(value.thresholds.batteryLevel, to: defaults)
            batteryTemperatureThreshold.write(
                value.thresholds.batteryTemperature,
                to: defaults
            )
            diskFreeThreshold.write(value.thresholds.diskFree, to: defaults)
            sustainDuration.write(value.sustainDuration, to: defaults)
        }
    }

    enum System {
        static let launchAtLogin = booleanSetting("launchAtLogin", default: false)
        static let definitions = [launchAtLogin.definition]

        static func write(_ value: SystemSettings, to defaults: UserDefaults) {
            launchAtLogin.write(value.launchAtLogin, to: defaults)
        }
    }

    static let definitions =
        Display.definitions + Sampling.definitions + Alerts.definitions + System.definitions

    static var registeredDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0.defaultValue) })
    }

    static func repairStoredValues(in defaults: UserDefaults) {
        for definition in definitions {
            guard let value = defaults.object(forKey: definition.key) else { continue }
            if !definition.isValid(value) {
                defaults.removeObject(forKey: definition.key)
            }
        }
    }

    static func reset(in defaults: UserDefaults) {
        for definition in definitions {
            defaults.removeObject(forKey: definition.key)
        }
    }

    private static func booleanSetting(
        _ key: String,
        default defaultValue: Bool
    ) -> StoredSetting<Bool> {
        StoredSetting(
            key: key,
            defaultValue: defaultValue,
            decode: { rawValue in
                guard let number = rawValue as? NSNumber,
                      CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    return nil
                }
                return number.boolValue
            },
            encode: { $0 }
        )
    }

    private static func doubleSetting(
        _ key: String,
        default defaultValue: Double,
        allowed: [Double]
    ) -> StoredSetting<Double> {
        StoredSetting(
            key: key,
            defaultValue: defaultValue,
            decode: { rawValue in
                guard let number = rawValue as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite,
                      allowed.contains(number.doubleValue) else {
                    return nil
                }
                return number.doubleValue
            },
            encode: { $0 }
        )
    }

    private static func integerSetting(
        _ key: String,
        default defaultValue: Int,
        allowed: [Int]
    ) -> StoredSetting<Int> {
        StoredSetting(
            key: key,
            defaultValue: defaultValue,
            decode: { rawValue in
                guard let number = rawValue as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite,
                      number.doubleValue == Double(number.intValue),
                      allowed.contains(number.intValue) else {
                    return nil
                }
                return number.intValue
            },
            encode: { $0 }
        )
    }

    private static func enumSetting<Value>(
        _ key: String,
        default defaultValue: Value
    ) -> StoredSetting<Value> where Value: RawRepresentable, Value.RawValue == String {
        StoredSetting(
            key: key,
            defaultValue: defaultValue,
            decode: { rawValue in
                guard let rawValue = rawValue as? String else { return nil }
                return Value(rawValue: rawValue)
            },
            encode: { $0.rawValue }
        )
    }

    private static func metricListSetting(
        _ key: String,
        default defaultValue: [PrimaryMetric],
        validate: @escaping ([PrimaryMetric]) -> Bool
    ) -> StoredSetting<[PrimaryMetric]> {
        StoredSetting(
            key: key,
            defaultValue: defaultValue,
            decode: { rawValue in
                guard let rawValues = rawValue as? [String] else { return nil }
                let metrics = rawValues.compactMap(PrimaryMetric.init(rawValue:))
                guard metrics.count == rawValues.count, validate(metrics) else {
                    return nil
                }
                return metrics
            },
            encode: { $0.map(\.rawValue) }
        )
    }
}
