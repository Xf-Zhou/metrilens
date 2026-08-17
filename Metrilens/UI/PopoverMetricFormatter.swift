import AppKit

enum PopoverMetricFormatter {
    static func cpuText(
        _ state: MetricState<CPUMetric>,
        language: AppLanguage
    ) -> String {
        guard let value = state.value else {
            return placeholder(state, language: language)
        }
        return String(
            format: "%.1f%%%@",
            value.percent,
            state.isStale ? language.localized(" · Stale") : ""
        )
    }

    static func memoryText(
        _ state: MetricState<MemoryMetric>,
        language: AppLanguage
    ) -> String {
        guard let value = state.value else {
            return placeholder(state, language: language)
        }
        let used = ByteCountFormatter.string(
            fromByteCount: Int64(value.usedBytes),
            countStyle: .memory
        )
        let total = ByteCountFormatter.string(
            fromByteCount: Int64(value.totalBytes),
            countStyle: .memory
        )
        return String(
            format: "\(used) / \(total) · %.0f%%%@",
            value.percent,
            state.isStale ? language.localized(" · Stale") : ""
        )
    }

    static func temperatureText(
        _ state: MetricState<Double>,
        language: AppLanguage
    ) -> String {
        guard let value = state.value else {
            return placeholder(state, language: language)
        }
        return String(
            format: "%.1f°C%@",
            value,
            state.isStale ? language.localized(" · Stale") : ""
        )
    }

    static func batteryPowerText(
        _ state: BatteryPowerState,
        language: AppLanguage
    ) -> String {
        switch state {
        case .charging: return language.localized("Charging")
        case .charged: return language.localized("Charged")
        case .discharging: return language.localized("On Battery")
        case .externalPower: return language.localized("Power Adapter")
        case .unknown: return language.localized("Unknown")
        }
    }

    static func batteryHealthText(
        _ health: BatteryHealth,
        language: AppLanguage
    ) -> String {
        switch health {
        case .good: return language.localized("Good")
        case .fair: return language.localized("batteryHealth.fair")
        case .poor: return language.localized("Poor")
        case .serviceRecommended:
            return language.localized("Service Recommended")
        case .unknown: return language.localized("Not Provided")
        }
    }

    static func rateText(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1_000, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        return String(
            format: value < 10 && index > 0 ? "%.1f %@" : "%.0f %@",
            value,
            units[index]
        )
    }

    static func byteText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(min(bytes, UInt64(Int64.max))),
            countStyle: .file
        )
    }

    static func summaryText(
        _ summary: MetricHistorySummary?,
        language: AppLanguage
    ) -> String {
        guard let summary else {
            return language.localized("summary.unavailable")
        }
        return String(
            format: language.localized("summary.available"),
            summary.average,
            summary.peak
        )
    }

    static func placeholder<T>(
        _ state: MetricState<T>,
        language: AppLanguage
    ) -> String {
        switch state {
        case .unsupported, .unavailable:
            return "—"
        case .available, .stale:
            return "—"
        }
    }

    static func failureReason<T>(
        _ state: MetricState<T>,
        language: AppLanguage
    ) -> String? {
        switch state {
        case let .unsupported(reason), let .unavailable(reason):
            return AppText.failureReason(reason, language: language)
        case .available, .stale:
            return nil
        }
    }

    static func isNoHardware<T>(_ state: MetricState<T>) -> Bool {
        if case .unsupported(.noHardware) = state { return true }
        return false
    }

    static func metricTextColor<T>(_ state: MetricState<T>) -> NSColor {
        state.isStale ? .secondaryLabelColor : .labelColor
    }

    static func temperatureTextColor(_ state: MetricState<Double>) -> NSColor {
        if state.isStale { return .secondaryLabelColor }
        guard let value = state.value else { return .labelColor }
        return color(
            severity: MetricPresentationPolicy.temperatureSeverity(value)
        )
    }

    static func color(severity: MetricVisualSeverity) -> NSColor {
        switch severity {
        case .normal: return .labelColor
        case .caution: return .systemYellow
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}
