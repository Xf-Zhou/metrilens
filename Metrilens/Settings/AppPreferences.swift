import Foundation

enum PrimaryMetric: String, CaseIterable {
    case cpu
    case memory
    case battery

    var menuTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .battery: return "电池温度"
        }
    }
}

struct PreferencesSnapshot: Equatable {
    let primaryMetric: PrimaryMetric
    let refreshInterval: TimeInterval
    let launchAtLogin: Bool
    let showsSparkline: Bool
}

final class AppPreferences {
    private enum Key {
        static let primaryMetric = "primaryMetric"
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let showsSparkline = "showsSparkline"
    }

    private let defaults: UserDefaults
    var onChange: ((PreferencesSnapshot) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.primaryMetric: PrimaryMetric.cpu.rawValue,
            Key.refreshInterval: 1.0,
            Key.launchAtLogin: false,
            Key.showsSparkline: true
        ])
    }

    var snapshot: PreferencesSnapshot {
        if ProcessInfo.processInfo.environment["METRILENS_PERF_MODE"] == "1" {
            return PreferencesSnapshot(
                primaryMetric: .cpu,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: true
            )
        }
        let metric = PrimaryMetric(
            rawValue: defaults.string(forKey: Key.primaryMetric) ?? ""
        ) ?? .cpu
        let interval = [1.0, 2.0, 5.0].contains(defaults.double(forKey: Key.refreshInterval))
            ? defaults.double(forKey: Key.refreshInterval)
            : 1.0
        return PreferencesSnapshot(
            primaryMetric: metric,
            refreshInterval: interval,
            launchAtLogin: defaults.bool(forKey: Key.launchAtLogin),
            showsSparkline: defaults.bool(forKey: Key.showsSparkline)
        )
    }

    func setPrimaryMetric(_ metric: PrimaryMetric) {
        defaults.set(metric.rawValue, forKey: Key.primaryMetric)
        notify()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard [1.0, 2.0, 5.0].contains(interval) else { return }
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

    private func notify() {
        onChange?(snapshot)
    }
}
