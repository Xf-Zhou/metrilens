import Foundation

struct AppBuildInformation: Equatable {
    let version: String?
    let build: String?

    static func current(bundle: Bundle = .main) -> AppBuildInformation {
        AppBuildInformation(
            version: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String
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
        language.localized("diagnostics.privacyDisclosure")
    }

    static func make(
        build: AppBuildInformation,
        context: DiagnosticContext,
        preferences: PreferencesSnapshot,
        snapshot: SystemSnapshot
    ) -> String {
        let language = preferences.display.language
        let heatDiagnosis = HeatDiagnosisAnalyzer.evaluate(snapshot)
        return [
            language.localized("Metrilens Diagnostics"),
            "app.version=\(build.version ?? "unknown")",
            "app.build=\(build.build ?? "unknown")",
            "system.os=\(context.operatingSystem)",
            "system.arch=\(context.architecture)",
            "system.low_power=\(yesNo(context.lowPowerModeEnabled))",
            "settings.primary_metric=\(preferences.display.primaryMetric.rawValue)",
            "settings.display_mode=\(preferences.display.statusDisplayMode.rawValue)",
            "settings.compact_metrics=\(preferences.display.compactMetrics.map(\.rawValue).joined(separator: ","))",
            "settings.metric_order=\(preferences.display.metricOrder.map(\.rawValue).joined(separator: ","))",
            "settings.status_separator=\(preferences.display.statusSeparator.rawValue)",
            "settings.status_decimals=\(preferences.display.statusDecimalPlaces)",
            "settings.refresh_seconds=\(format(preferences.sampling.refreshInterval))",
            "settings.launch_at_login=\(yesNo(preferences.system.launchAtLogin))",
            "settings.sparkline=\(yesNo(preferences.sampling.showsSparkline))",
            "settings.language=\(preferences.display.language.rawValue)",
            "settings.alerts_enabled=\(yesNo(preferences.alerts.enabled))",
            "settings.cpu_alert_enabled=\(yesNo(preferences.alerts.enabledKinds.contains(.cpu)))",
            "settings.memory_alert_enabled=\(yesNo(preferences.alerts.enabledKinds.contains(.memory)))",
            "settings.thermal_alert_enabled=\(yesNo(preferences.alerts.enabledKinds.contains(.thermal)))",
            "settings.battery_level_alert_enabled=\(yesNo(preferences.alerts.enabledKinds.contains(.batteryLevel)))",
            "settings.battery_temperature_alert_enabled=\(yesNo(preferences.alerts.enabledKinds.contains(.batteryTemperature)))",
            "settings.disk_free_alert_enabled=\(yesNo(preferences.alerts.enabledKinds.contains(.diskFree)))",
            "settings.cpu_alert_threshold=\(format(preferences.alerts.thresholds.cpu))%",
            "settings.memory_alert_threshold=\(format(preferences.alerts.thresholds.memory))%",
            "settings.battery_level_alert_threshold=\(format(preferences.alerts.thresholds.batteryLevel))%",
            "settings.battery_temperature_alert_threshold=\(format(preferences.alerts.thresholds.batteryTemperature))C",
            "settings.disk_free_alert_threshold=\(format(preferences.alerts.thresholds.diskFree))%",
            "settings.alert_sustain_seconds=\(format(preferences.alerts.sustainDuration))",
            "sampling.running=\(yesNo(snapshot.samplingRuntime.isRunning))",
            "sampling.sleeping=\(yesNo(snapshot.samplingRuntime.isSleeping))",
            "sampling.popover_visible=\(yesNo(snapshot.samplingRuntime.isPopoverVisible))",
            "sampling.cpu_period=\(period(snapshot, .cpu))",
            "sampling.memory_period=\(period(snapshot, .memory))",
            "sampling.battery_period=\(period(snapshot, .battery))",
            "sampling.network_period=\(period(snapshot, .network))",
            "sampling.disk_period=\(period(snapshot, .disk))",
            "metrics.cpu=\(describePercent(snapshot.cpu.map(\.percent)))",
            "metrics.cpu_average=\(describeSummary(snapshot.cpuHistorySummary, keyPath: \.average))",
            "metrics.cpu_peak=\(describeSummary(snapshot.cpuHistorySummary, keyPath: \.peak))",
            "metrics.memory=\(describePercent(snapshot.memory.map(\.percent)))",
            "metrics.memory_average=\(describeSummary(snapshot.memoryHistorySummary, keyPath: \.average))",
            "metrics.memory_peak=\(describeSummary(snapshot.memoryHistorySummary, keyPath: \.peak))",
            "metrics.battery_temperature=\(describeTemperature(snapshot.batteryTemperature))",
            "metrics.battery_level=\(describeBatteryLevel(snapshot.battery))",
            "metrics.battery_power=\(describe(snapshot.battery) { $0.powerState.rawValue })",
            "metrics.battery_cycles=\(describeBatteryCycles(snapshot.battery))",
            "metrics.battery_health=\(describe(snapshot.battery) { $0.health.rawValue })",
            "metrics.battery_session_maximum=\(describeTemperature(snapshot.batterySessionMaximumTemperature))",
            "metrics.battery_maximum=\(describeTemperature(snapshot.batteryMaximumTemperature))",
            "metrics.network_download=\(describeNetwork(snapshot.network, keyPath: \.downloadBytesPerSecond))",
            "metrics.network_upload=\(describeNetwork(snapshot.network, keyPath: \.uploadBytesPerSecond))",
            "metrics.disk_used=\(describeDisk(snapshot.disk, keyPath: \.usedPercent))",
            "metrics.disk_free=\(describeDisk(snapshot.disk, keyPath: \.freePercent))",
            "metrics.thermal=\(thermalName(snapshot.thermalLevel))",
            "heat.severity=\(heatDiagnosis.severity.rawValue)",
            "heat.evidence=\(heatDiagnosis.evidence.map(\.rawValue).joined(separator: ","))",
            "heat.recommendations=\(heatDiagnosis.recommendations.map(\.rawValue).joined(separator: ","))",
            "metrics.recent_errors=\(describeErrors(snapshot.recentErrors))"
        ].joined(separator: "\n")
    }

    private static func describePercent(_ state: MetricState<Double>) -> String {
        describe(state) { "\(format($0))%" }
    }

    private static func describeTemperature(_ state: MetricState<Double>) -> String {
        describe(state) { "\(format($0))C" }
    }

    private static func describeBatteryLevel(
        _ state: MetricState<BatteryMetric>
    ) -> String {
        describe(state) { "\(format($0.levelPercent))%" }
    }

    private static func describeBatteryCycles(
        _ state: MetricState<BatteryMetric>
    ) -> String {
        describe(state) { $0.cycleCount.map(String.init) ?? "unavailable" }
    }

    private static func describeNetwork(
        _ state: MetricState<NetworkMetric>,
        keyPath: KeyPath<NetworkMetric, Double>
    ) -> String {
        describe(state) { "\(format($0[keyPath: keyPath]))Bps" }
    }

    private static func describeDisk(
        _ state: MetricState<DiskCapacityMetric>,
        keyPath: KeyPath<DiskCapacityMetric, Double>
    ) -> String {
        describe(state) { "\(format($0[keyPath: keyPath]))%" }
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
        case .noActiveInterface: return "no_active_interface"
        case .fieldMissing: return "field_missing"
        case .unsupportedEncoding: return "unsupported_encoding"
        case .counterOverflow: return "counter_overflow"
        case .outOfRange: return "out_of_range"
        case .outlierJump: return "outlier_jump"
        case .fileSystemFailure: return "filesystem_failure"
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
        case .network: return "network"
        case .disk: return "disk"
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
