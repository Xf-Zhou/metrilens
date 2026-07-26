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
    static let privacyDisclosure = privacyDisclosure(language: .simplifiedChinese)

    static func privacyDisclosure(language: AppLanguage) -> String {
        language.text(
            "诊断信息仅包含 App 版本与构建号、macOS 版本、系统架构、低电量模式状态、"
                + "应用设置、采样状态、指标状态和最近的指标读取错误；"
                + "不包含用户名、主机名、序列号、文件路径、进程 ID 或网络地址。",
            "Diagnostics include only the app version and build, macOS version, architecture, "
                + "Low Power Mode, app settings, sampling state, metric state, and recent metric "
                + "read errors. They do not include usernames, hostnames, serial numbers, file "
                + "paths, process IDs, or network addresses."
        )
    }

    static func make(
        build: AppBuildInformation,
        context: DiagnosticContext,
        preferences: PreferencesSnapshot,
        snapshot: SystemSnapshot
    ) -> String {
        let language = preferences.language
        return [
            language.text("Metrilens 诊断信息", "Metrilens Diagnostics"),
            "app.version=\(build.version)",
            "app.build=\(build.build)",
            "system.os=\(context.operatingSystem)",
            "system.arch=\(context.architecture)",
            "system.low_power=\(yesNo(context.lowPowerModeEnabled))",
            "settings.primary_metric=\(preferences.primaryMetric.rawValue)",
            "settings.display_mode=\(preferences.statusDisplayMode.rawValue)",
            "settings.compact_metrics=\(preferences.compactMetrics.map(\.rawValue).joined(separator: ","))",
            "settings.refresh_seconds=\(format(preferences.refreshInterval))",
            "settings.launch_at_login=\(yesNo(preferences.launchAtLogin))",
            "settings.sparkline=\(yesNo(preferences.showsSparkline))",
            "settings.language=\(preferences.language.rawValue)",
            "settings.alerts_enabled=\(yesNo(preferences.alertsEnabled))",
            "settings.cpu_alert_threshold=\(format(preferences.cpuAlertThreshold))%",
            "settings.memory_alert_threshold=\(format(preferences.memoryAlertThreshold))%",
            "settings.alert_sustain_seconds=\(format(preferences.alertSustainDuration))",
            "sampling.running=\(yesNo(snapshot.samplingRuntime.isRunning))",
            "sampling.sleeping=\(yesNo(snapshot.samplingRuntime.isSleeping))",
            "sampling.popover_visible=\(yesNo(snapshot.samplingRuntime.isPopoverVisible))",
            "sampling.cpu_period=\(period(snapshot, .cpu))",
            "sampling.memory_period=\(period(snapshot, .memory))",
            "sampling.battery_period=\(period(snapshot, .battery))",
            "metrics.cpu=\(describePercent(snapshot.cpu.map(\.percent)))",
            "metrics.cpu_average=\(describeSummary(snapshot.cpuHistorySummary, keyPath: \.average))",
            "metrics.cpu_peak=\(describeSummary(snapshot.cpuHistorySummary, keyPath: \.peak))",
            "metrics.memory=\(describePercent(snapshot.memory.map(\.percent)))",
            "metrics.memory_average=\(describeSummary(snapshot.memoryHistorySummary, keyPath: \.average))",
            "metrics.memory_peak=\(describeSummary(snapshot.memoryHistorySummary, keyPath: \.peak))",
            "metrics.battery_temperature=\(describeTemperature(snapshot.batteryTemperature))",
            "metrics.battery_session_maximum=\(describeTemperature(snapshot.batterySessionMaximumTemperature))",
            "metrics.battery_maximum=\(describeTemperature(snapshot.batteryMaximumTemperature))",
            "metrics.thermal=\(thermalName(snapshot.thermalLevel))",
            "metrics.recent_errors=\(describeErrors(snapshot.recentErrors))"
        ].joined(separator: "\n")
    }

    private static func describePercent(_ state: MetricState<Double>) -> String {
        describe(state) { "\(format($0))%" }
    }

    private static func describeTemperature(_ state: MetricState<Double>) -> String {
        describe(state) { "\(format($0))C" }
    }

    private static func describeSummary(
        _ summary: MetricHistorySummary?,
        keyPath: KeyPath<MetricHistorySummary, Double>
    ) -> String {
        guard let summary else { return "unavailable" }
        return "\(format(summary[keyPath: keyPath]))%"
    }

    private static func period(
        _ snapshot: SystemSnapshot,
        _ provider: ProviderID
    ) -> String {
        guard let value = snapshot.samplingRuntime.effectivePeriods[provider] else {
            return "paused"
        }
        return format(value)
    }

    private static func describeErrors(_ errors: [RecentMetricError]) -> String {
        guard !errors.isEmpty else { return "none" }
        return errors.map {
            "\(providerName($0.provider)):\(failureName($0.failure))@\(isoFormatter.string(from: $0.wallTime))"
        }.joined(separator: ",")
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

    private static func providerName(_ provider: ProviderID) -> String {
        switch provider {
        case .cpu: return "cpu"
        case .memory: return "memory"
        case .battery: return "battery"
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
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
