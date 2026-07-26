import AppKit

struct StatusMetricPresentation: Equatable {
    let title: String
    let staleStamp: SampleStamp?
}

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var primaryMetric: PrimaryMetric
    private var didSignalReadiness = false

    var onToggle: ((NSStatusBarButton) -> Void)?

    init(primaryMetric: PrimaryMetric) {
        self.primaryMetric = primaryMetric
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = "Metrilens 系统状态"
            button.setAccessibilityLabel("Metrilens 系统状态")
            button.setAccessibilityHelp("打开 CPU、内存、电池温度和系统热状态")
            setTitle("CPU —", warning: false)
            TaskPowerProbe.signalReadyIfRequested()
            didSignalReadiness = true
        }
    }

    func setPrimaryMetric(_ metric: PrimaryMetric) {
        primaryMetric = metric
    }

    func update(snapshot: SystemSnapshot) {
        let presentation = Self.presentation(primaryMetric: primaryMetric, snapshot: snapshot)
        let warning = snapshot.thermalLevel == .serious || snapshot.thermalLevel == .critical
        setTitle(presentation.title, warning: warning, stale: presentation.staleStamp != nil)
        var accessibilityValue = presentation.title
        if presentation.staleStamp != nil {
            accessibilityValue += "，数据已过期"
        }
        if warning {
            accessibilityValue += "，系统热状态警告"
        }
        statusItem.button?.setAccessibilityValue(accessibilityValue)
        if let stamp = presentation.staleStamp {
            statusItem.button?.toolTip =
                "Metrilens 系统状态\n数据已过期，采样于 \(Self.timeFormatter.string(from: stamp.wallTime))"
        } else {
            statusItem.button?.toolTip = "Metrilens 系统状态"
        }
    }

    private func setTitle(_ title: String, warning: Bool, stale: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: warning
                ? NSColor.systemOrange
                : (stale ? NSColor.secondaryLabelColor : NSColor.labelColor)
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
        switch primaryMetric {
        case .cpu:
            return percentTitle(prefix: "CPU", state: snapshot.cpu.map(\.percent))
        case .memory:
            return percentTitle(prefix: "MEM", state: snapshot.memory.map(\.percent))
        case .battery:
            return temperatureTitle(state: snapshot.batteryTemperature)
        }
    }

    private static func percentTitle<T>(
        prefix: String,
        state: MetricState<T>
    ) -> StatusMetricPresentation where T: PercentProviding {
        guard let value = state.value else {
            return StatusMetricPresentation(title: "\(prefix) —", staleStamp: nil)
        }
        let staleStamp = state.isStale ? state.stamp : nil
        let suffix = staleStamp == nil ? "" : " ·"
        return StatusMetricPresentation(
            title: String(format: "\(prefix) %.0f%%%@", value.percentValue, suffix),
            staleStamp: staleStamp
        )
    }

    private static func temperatureTitle(
        state: MetricState<Double>
    ) -> StatusMetricPresentation {
        guard let value = state.value else {
            return StatusMetricPresentation(title: "BAT —", staleStamp: nil)
        }
        let staleStamp = state.isStale ? state.stamp : nil
        let suffix = staleStamp == nil ? "" : " ·"
        return StatusMetricPresentation(
            title: String(format: "BAT %.1f°%@", value, suffix),
            staleStamp: staleStamp
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
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
