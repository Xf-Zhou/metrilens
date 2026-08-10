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
    private var displayedTitle = "CPU —"
    private var displayedSeverity = MetricVisualSeverity.normal
    private var displayedAsStale = false
    private var isPopoverVisible = false

    var onToggle: ((NSStatusBarButton) -> Void)?

    init(preferences: PreferencesSnapshot) {
        self.preferences = preferences
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.setAccessibilityIdentifier("metrilens.statusItem")
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

    func setPopoverVisible(_ visible: Bool) {
        guard visible != isPopoverVisible else { return }
        isPopoverVisible = visible
        statusItem.button?.highlight(visible)
        applyDisplayedTitle()
    }

    func accessibilityValueForTesting() -> String? {
        statusItem.button?.accessibilityValue() as? String
    }

    func isHighlightedForTesting() -> Bool {
        statusItem.button?.cell?.isHighlighted ?? false
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
            accessibilityValue += preferences.display.language.localized(", data is stale")
        }
        if MetricPresentationPolicy.thermalSeverity(snapshot.thermalLevel) >= .warning {
            accessibilityValue += preferences.display.language.localized(", system thermal warning")
        }
        statusItem.button?.setAccessibilityValue(accessibilityValue)
        if let stamp = presentation.staleStamps.max(by: {
            $0.wallTime < $1.wallTime
        }) {
            statusItem.button?.toolTip =
                preferences.display.language.localized(
                    "status.staleTooltip",
                    arguments: Self.timeFormatter.string(from: stamp.wallTime)
                )
        } else {
            statusItem.button?.toolTip = preferences.display.language.localized("Metrilens System Status")
        }
    }

    private func setTitle(
        _ title: String,
        severity: MetricVisualSeverity,
        stale: Bool = false
    ) {
        displayedTitle = title
        displayedSeverity = severity
        displayedAsStale = stale
        applyDisplayedTitle()
        statusItem.button?.setAccessibilityValue(title)
    }

    private func applyDisplayedTitle() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: Self.statusColor(
                severity: displayedSeverity,
                stale: displayedAsStale,
                selected: isPopoverVisible
            )
        ]
        statusItem.button?.attributedTitle = NSAttributedString(
            string: displayedTitle,
            attributes: attributes
        )
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
                display: DisplaySettings(primaryMetric: primaryMetric)
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
                decimalPlaces: preferences.display.statusDecimalPlaces,
                language: preferences.display.language
            )
        }
        let staleStamps = segments.compactMap(\.staleStamp)
        let staleSuffix = staleStamps.isEmpty ? "" : " ⏱"
        return StatusMetricPresentation(
            title: segments.map(\.title).joined(
                separator: preferences.display.statusSeparator.text
            ) + staleSuffix,
            staleStamps: staleStamps,
            severity: segments.map(\.severity).max() ?? .normal
        )
    }

    private static func segment(
        metric: PrimaryMetric,
        snapshot: SystemSnapshot,
        decimalPlaces: Int,
        language: AppLanguage
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
                prefix: language.localized("RAM"),
                state: snapshot.memory.map(\.percent),
                decimalPlaces: decimalPlaces
            )
        case .battery:
            return temperatureSegment(
                state: snapshot.batteryTemperature,
                decimalPlaces: max(1, decimalPlaces),
                language: language
            )
        case .network:
            return networkSegment(
                state: snapshot.network,
                decimalPlaces: decimalPlaces,
                language: language
            )
        case .disk:
            return diskSegment(
                state: snapshot.disk,
                decimalPlaces: decimalPlaces,
                language: language
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
        decimalPlaces: Int,
        language: AppLanguage
    ) -> MetricSegment {
        let prefix = language.localized("Batt")
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
                staleStamp: nil,
                severity: .normal
            )
        }
        return MetricSegment(
            title: String(format: "\(prefix) %.\(decimalPlaces)f°C", value),
            staleStamp: state.isStale ? state.stamp : nil,
            severity: state.isStale
                ? .normal
                : MetricPresentationPolicy.temperatureSeverity(value)
        )
    }

    private static func networkSegment(
        state: MetricState<NetworkMetric>,
        decimalPlaces: Int,
        language: AppLanguage
    ) -> MetricSegment {
        let prefix = language.localized("Net")
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
                staleStamp: nil,
                severity: .normal
            )
        }
        return MetricSegment(
            title: "\(prefix) ↓\(rate(value.downloadBytesPerSecond, decimalPlaces: decimalPlaces)) "
                + "↑\(rate(value.uploadBytesPerSecond, decimalPlaces: decimalPlaces))",
            staleStamp: state.isStale ? state.stamp : nil,
            severity: .normal
        )
    }

    private static func diskSegment(
        state: MetricState<DiskCapacityMetric>,
        decimalPlaces: Int,
        language: AppLanguage
    ) -> MetricSegment {
        let prefix = language.localized("Free")
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
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
                format: "\(prefix) %.\(decimalPlaces)f%%",
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
        statusItem.button?.toolTip = preferences.display.language.localized("Metrilens System Status")
        statusItem.button?.setAccessibilityLabel(
            preferences.display.language.localized("Metrilens System Status")
        )
        statusItem.button?.setAccessibilityHelp(
            preferences.display.language.localized("Open CPU, memory, battery, network, disk, and heat diagnostics")
        )
    }

    static func statusColor(
        severity: MetricVisualSeverity,
        stale: Bool,
        selected: Bool
    ) -> NSColor {
        if selected {
            return .selectedMenuItemTextColor
        }
        if stale && severity == .normal {
            return .secondaryLabelColor
        }
        switch severity {
        case .normal: return .labelColor
        case .caution: return .systemOrange.withAlphaComponent(0.72)
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
