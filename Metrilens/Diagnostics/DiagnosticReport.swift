import Foundation

struct AppBuildInformation: Equatable {
    let version: String
    let build: String

    static func current(bundle: Bundle = .main) -> AppBuildInformation {
        AppBuildInformation(
            version: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "未知",
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "未知"
        )
    }
}

struct DiagnosticContext: Equatable {
    let operatingSystem: String
    let architecture: String
    let lowPowerModeEnabled: Bool

    static func current(processInfo: ProcessInfo = .processInfo) -> DiagnosticContext {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unsupported"
        #endif
        return DiagnosticContext(
            operatingSystem: processInfo.operatingSystemVersionString,
            architecture: architecture,
            lowPowerModeEnabled: processInfo.isLowPowerModeEnabled
        )
    }
}

enum DiagnosticReport {
    static let privacyDisclosure =
        "诊断信息仅包含 App 版本与构建号、macOS 版本、系统架构、低电量模式状态、应用设置和指标状态；"
        + "不包含用户名、主机名、序列号、文件路径或网络地址。"

    static func make(
        build: AppBuildInformation,
        context: DiagnosticContext,
        preferences: PreferencesSnapshot,
        snapshot: SystemSnapshot
    ) -> String {
        [
            "Metrilens 诊断信息",
            "app.version=\(build.version)",
            "app.build=\(build.build)",
            "system.os=\(context.operatingSystem)",
            "system.arch=\(context.architecture)",
            "system.low_power=\(yesNo(context.lowPowerModeEnabled))",
            "settings.primary_metric=\(preferences.primaryMetric.rawValue)",
            "settings.refresh_seconds=\(format(preferences.refreshInterval))",
            "settings.launch_at_login=\(yesNo(preferences.launchAtLogin))",
            "settings.sparkline=\(yesNo(preferences.showsSparkline))",
            "metrics.cpu=\(describePercent(snapshot.cpu.map(\.percent)))",
            "metrics.memory=\(describePercent(snapshot.memory.map(\.percent)))",
            "metrics.battery_temperature=\(describeTemperature(snapshot.batteryTemperature))",
            "metrics.battery_maximum=\(describeTemperature(snapshot.batteryMaximumTemperature))",
            "metrics.thermal=\(thermalName(snapshot.thermalLevel))"
        ].joined(separator: "\n")
    }

    private static func describePercent(_ state: MetricState<Double>) -> String {
        describe(state) { "\(format($0))%" }
    }

    private static func describeTemperature(_ state: MetricState<Double>) -> String {
        describe(state) { "\(format($0))C" }
    }

    private static func describe<T>(
        _ state: MetricState<T>,
        value: (T) -> String
    ) -> String {
        switch state {
        case let .available(metric, _):
            return "available:\(value(metric))"
        case let .stale(metric, _):
            return "stale:\(value(metric))"
        case let .unavailable(error):
            return "unavailable:\(failureName(error))"
        case let .unsupported(error):
            return "unsupported:\(failureName(error))"
        }
    }

    private static func failureName(_ failure: MetricFailure) -> String {
        switch failure {
        case .noHardware: return "no_hardware"
        case .fieldMissing: return "field_missing"
        case .unsupportedEncoding: return "unsupported_encoding"
        case .counterOverflow: return "counter_overflow"
        case .outOfRange: return "out_of_range"
        case .outlierJump: return "outlier_jump"
        case .iokitFailure: return "iokit_failure"
        case .machFailure: return "mach_failure"
        }
    }

    private static func thermalName(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private extension MetricState {
    func map<M>(_ transform: (Value) -> M) -> MetricState<M> {
        switch self {
        case let .available(value, stamp): return .available(transform(value), stamp)
        case let .stale(value, stamp): return .stale(transform(value), stamp)
        case let .unavailable(error): return .unavailable(error)
        case let .unsupported(error): return .unsupported(error)
        }
    }
}
