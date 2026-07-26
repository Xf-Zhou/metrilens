import AppKit

struct StatusMetricPresentation: Equatable {
    let title: String
    let staleStamps: [SampleStamp]
    let severity: MetricVisualSeverity
}

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var preferences: PreferencesSnapshot
    private var didSignalReadiness = false

    var onToggle: ((NSStatusBarButton) -> Void)?

    init(preferences: PreferencesSnapshot) {
        self.preferences = preferences
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            updateLocalizedMetadata()
            setTitle("CPU —", severity: .normal)
            TaskPowerProbe.signalReadyIfRequested()
            didSignalReadiness = true
        }
    }

    func setPreferences(_ preferences: PreferencesSnapshot) {
        self.preferences = preferences
        updateLocalizedMetadata()
    }

    func update(snapshot: SystemSnapshot) {
        let presentation = Self.presentation(preferences: preferences, snapshot: snapshot)
        let severity = max(
            presentation.severity,
            MetricPresentationPolicy.thermalSeverity(snapshot.thermalLevel)
        )
        setTitle(
            presentation.title,
            severity: severity,
            stale: !presentation.staleStamps.isEmpty
        )
        var accessibilityValue = presentation.title
        if !presentation.staleStamps.isEmpty {
            accessibilityValue += preferences.language.text(
                "，数据已过期",
                ", data is stale"
            )
        }
        if MetricPresentationPolicy.thermalSeverity(snapshot.thermalLevel) >= .warning {
            accessibilityValue += preferences.language.text(
                "，系统热状态警告",
                ", system thermal warning"
            )
        }
        statusItem.button?.setAccessibilityValue(accessibilityValue)
        if let stamp = presentation.staleStamps.max(by: {
            $0.wallTime < $1.wallTime
        }) {
            statusItem.button?.toolTip =
                preferences.language.text(
                    "Metrilens 系统状态\n数据已过期，采样于 \(Self.timeFormatter.string(from: stamp.wallTime))",
                    "Metrilens System Status\nData is stale; sampled at \(Self.timeFormatter.string(from: stamp.wallTime))"
                )
        } else {
            statusItem.button?.toolTip = preferences.language.text(
                "Metrilens 系统状态",
                "Metrilens System Status"
            )
        }
    }

    private func setTitle(
        _ title: String,
        severity: MetricVisualSeverity,
        stale: Bool = false
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: Self.color(severity: severity, stale: stale)
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        statusItem.button?.setAccessibilityValue(title)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if !didSignalReadiness {
            TaskPowerProbe.signalReadyIfRequested()
            didSignalReadiness = true
        }
        onToggle?(button)
    }

    static func presentation(
        primaryMetric: PrimaryMetric,
        snapshot: SystemSnapshot
    ) -> StatusMetricPresentation {
        presentation(
            preferences: PreferencesSnapshot(
                primaryMetric: primaryMetric,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: true
            ),
            snapshot: snapshot
        )
    }

    static func presentation(
        preferences: PreferencesSnapshot,
        snapshot: SystemSnapshot
    ) -> StatusMetricPresentation {
        let metrics = preferences.displayedMetrics
        let segments = metrics.map {
            segment(
                metric: $0,
                snapshot: snapshot,
                decimalPlaces: preferences.statusDecimalPlaces
            )
        }
        let staleStamps = segments.compactMap(\.staleStamp)
        let staleSuffix = staleStamps.isEmpty ? "" : " ⏱"
        return StatusMetricPresentation(
            title: segments.map(\.title).joined(
                separator: preferences.statusSeparator.text
            ) + staleSuffix,
            staleStamps: staleStamps,
            severity: segments.map(\.severity).max() ?? .normal
        )
    }

    private static func segment(
        metric: PrimaryMetric,
        snapshot: SystemSnapshot,
        decimalPlaces: Int
    ) -> MetricSegment {
        switch metric {
        case .cpu:
            return percentSegment(
                prefix: "CPU",
                state: snapshot.cpu.map(\.percent),
                decimalPlaces: decimalPlaces
            )
        case .memory:
            return percentSegment(
                prefix: "MEM",
                state: snapshot.memory.map(\.percent),
                decimalPlaces: decimalPlaces
            )
        case .battery:
            return temperatureSegment(
                state: snapshot.batteryTemperature,
                decimalPlaces: max(1, decimalPlaces)
            )
        case .network:
            return networkSegment(
                state: snapshot.network,
                decimalPlaces: decimalPlaces
            )
        case .disk:
            return diskSegment(
                state: snapshot.disk,
                decimalPlaces: decimalPlaces
            )
        }
    }

    private static func percentSegment<T>(
        prefix: String,
        state: MetricState<T>,
        decimalPlaces: Int
    ) -> MetricSegment where T: PercentProviding {
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
                staleStamp: nil,
                severity: .normal
            )
        }
        return MetricSegment(
            title: String(
                format: "\(prefix) %.\(decimalPlaces)f%%",
                value.percentValue
            ),
            staleStamp: state.isStale ? state.stamp : nil,
            severity: .normal
        )
    }

    private static func temperatureSegment(
        state: MetricState<Double>,
        decimalPlaces: Int
    ) -> MetricSegment {
        guard let value = state.value else {
            return MetricSegment(
                title: "BAT —",
                staleStamp: nil,
                severity: .normal
            )
        }
        return MetricSegment(
            title: String(format: "BAT %.\(decimalPlaces)f°", value),
            staleStamp: state.isStale ? state.stamp : nil,
            severity: state.isStale
                ? .normal
                : MetricPresentationPolicy.temperatureSeverity(value)
        )
    }

    private static func networkSegment(
        state: MetricState<NetworkMetric>,
        decimalPlaces: Int
    ) -> MetricSegment {
        guard let value = state.value else {
            return MetricSegment(
                title: "NET —",
                staleStamp: nil,
                severity: .normal
            )
        }
        return MetricSegment(
            title: "↓\(rate(value.downloadBytesPerSecond, decimalPlaces: decimalPlaces)) "
                + "↑\(rate(value.uploadBytesPerSecond, decimalPlaces: decimalPlaces))",
            staleStamp: state.isStale ? state.stamp : nil,
            severity: .normal
        )
    }

    private static func diskSegment(
        state: MetricState<DiskCapacityMetric>,
        decimalPlaces: Int
    ) -> MetricSegment {
        guard let value = state.value else {
            return MetricSegment(
                title: "DISK —",
                staleStamp: nil,
                severity: .normal
            )
        }
        let severity: MetricVisualSeverity
        if state.isStale {
            severity = .normal
        } else {
            severity =
                value.freePercent <= 5 ? .warning
                : value.freePercent <= 10 ? .caution
                : .normal
        }
        return MetricSegment(
            title: String(
                format: "DISK %.\(decimalPlaces)f%%",
                value.freePercent
            ),
            staleStamp: state.isStale ? state.stamp : nil,
            severity: severity
        )
    }

    private static func rate(
        _ bytesPerSecond: Double,
        decimalPlaces: Int
    ) -> String {
        let units = ["B/s", "K/s", "M/s", "G/s"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1_000, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        return String(format: "%.\(decimalPlaces)f%@", value, units[index])
    }

    private func updateLocalizedMetadata() {
        statusItem.button?.toolTip = preferences.language.text(
            "Metrilens 系统状态",
            "Metrilens System Status"
        )
        statusItem.button?.setAccessibilityLabel(
            preferences.language.text(
                "Metrilens 系统状态",
                "Metrilens System Status"
            )
        )
        statusItem.button?.setAccessibilityHelp(
            preferences.language.text(
                "打开 CPU、内存、电池、网络、磁盘和发热诊断",
                "Open CPU, memory, battery, network, disk, and heat diagnostics"
            )
        )
    }

    private static func color(
        severity: MetricVisualSeverity,
        stale: Bool
    ) -> NSColor {
        if stale && severity == .normal {
            return .secondaryLabelColor
        }
        switch severity {
        case .normal: return .labelColor
        case .caution: return .systemYellow
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct MetricSegment {
    let title: String
    let staleStamp: SampleStamp?
    let severity: MetricVisualSeverity
}

private protocol PercentProviding {
    var percentValue: Double { get }
}

extension CPUMetric: PercentProviding {
    var percentValue: Double { percent }
}

extension MemoryMetric: PercentProviding {
    var percentValue: Double { percent }
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

extension Double: PercentProviding {
    fileprivate var percentValue: Double { self }
}
