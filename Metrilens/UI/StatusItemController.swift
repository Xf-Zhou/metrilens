import AppKit

struct StatusMetricPresentation: Equatable {
    let title: String
    let visualSegments: [StatusVisualSegment]
    let separator: String
    let trailingText: String
    let staleStamps: [SampleStamp]
    let severity: MetricVisualSeverity
}

enum StatusVisualSegment: Equatable {
    case metric(label: String, value: String, reservedValue: String)
    case network(
        label: String,
        download: String,
        upload: String,
        reservedRate: String,
        layout: NetworkStatusLayout
    )
}

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var preferences: PreferencesSnapshot
    private var didSignalReadiness = false
    private var displayedVisualSegments: [StatusVisualSegment] = [
        .metric(label: "CPU", value: "—", reservedValue: "100%")
    ]
    private var displayedSeparator = ""
    private var displayedTrailingText = ""
    private var displayedSeverity = MetricVisualSeverity.normal
    private var displayedAsStale = false
    private var isPopoverVisible = false
    private var latestSnapshot: SystemSnapshot?

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
            setTitle(
                StatusMetricPresentation(
                    title: "CPU —",
                    visualSegments: [
                        .metric(label: "CPU", value: "—", reservedValue: "100%")
                    ],
                    separator: "",
                    trailingText: "",
                    staleStamps: [],
                    severity: .normal
                )
            )
            TaskPowerProbe.signalReadyIfRequested()
            didSignalReadiness = true
        }
    }

    func setPreferences(_ preferences: PreferencesSnapshot) {
        self.preferences = preferences
        updateLocalizedMetadata()
        if let latestSnapshot {
            update(snapshot: latestSnapshot)
        }
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
        latestSnapshot = snapshot
        let presentation = Self.presentation(preferences: preferences, snapshot: snapshot)
        let severity = max(
            presentation.severity,
            MetricPresentationPolicy.thermalSeverity(snapshot.thermalLevel)
        )
        setTitle(presentation, severity: severity)
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
        _ presentation: StatusMetricPresentation,
        severity: MetricVisualSeverity? = nil
    ) {
        displayedVisualSegments = presentation.visualSegments
        displayedSeparator = presentation.separator
        displayedTrailingText = presentation.trailingText
        displayedSeverity = severity ?? presentation.severity
        displayedAsStale = !presentation.staleStamps.isEmpty
        applyDisplayedTitle()
        statusItem.button?.setAccessibilityValue(presentation.title)
    }

    private func applyDisplayedTitle() {
        let color = Self.statusColor(
            severity: displayedSeverity,
            stale: displayedAsStale,
            selected: isPopoverVisible
        )
        let image = StatusItemTitleRenderer.image(
            segments: displayedVisualSegments,
            separator: displayedSeparator,
            trailingText: displayedTrailingText,
            color: color
        )
        image.accessibilityDescription = displayedVisualSegments.accessibilityText(
            separator: displayedSeparator,
            trailingText: displayedTrailingText
        )
        statusItem.button?.title = ""
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        statusItem.length = ceil(image.size.width) + 12
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
                networkLayout: preferences.display.networkStatusLayout,
                language: preferences.display.language
            )
        }
        let staleStamps = segments.compactMap(\.staleStamp)
        let staleSuffix = staleStamps.isEmpty ? "" : " ⏱"
        return StatusMetricPresentation(
            title: segments.map(\.title).joined(
                separator: preferences.display.statusSeparator.text
            ) + staleSuffix,
            visualSegments: segments.map(\.visual),
            separator: preferences.display.statusSeparator.text,
            trailingText: staleSuffix,
            staleStamps: staleStamps,
            severity: segments.map(\.severity).max() ?? .normal
        )
    }

    private static func segment(
        metric: PrimaryMetric,
        snapshot: SystemSnapshot,
        decimalPlaces: Int,
        networkLayout: NetworkStatusLayout,
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
                layout: networkLayout,
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
        let reservedValue = percentPlaceholder(decimalPlaces: decimalPlaces)
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
                visual: .metric(
                    label: prefix,
                    value: "—",
                    reservedValue: reservedValue
                ),
                staleStamp: nil,
                severity: .normal
            )
        }
        let formattedValue = String(
            format: "%.\(decimalPlaces)f%%",
            value.percentValue
        )
        let title = "\(prefix) \(formattedValue)"
        return MetricSegment(
            title: title,
            visual: .metric(
                label: prefix,
                value: formattedValue,
                reservedValue: reservedValue
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
        let reservedValue = temperaturePlaceholder(decimalPlaces: decimalPlaces)
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
                visual: .metric(
                    label: prefix,
                    value: "—",
                    reservedValue: reservedValue
                ),
                staleStamp: nil,
                severity: .normal
            )
        }
        let formattedValue = String(format: "%.\(decimalPlaces)f°C", value)
        let title = "\(prefix) \(formattedValue)"
        return MetricSegment(
            title: title,
            visual: .metric(
                label: prefix,
                value: formattedValue,
                reservedValue: reservedValue
            ),
            staleStamp: state.isStale ? state.stamp : nil,
            severity: state.isStale
                ? .normal
                : MetricPresentationPolicy.temperatureSeverity(value)
        )
    }

    private static func networkSegment(
        state: MetricState<NetworkMetric>,
        decimalPlaces: Int,
        layout: NetworkStatusLayout,
        language: AppLanguage
    ) -> MetricSegment {
        let prefix = language.localized("Net")
        let reservedRate = ratePlaceholder(decimalPlaces: decimalPlaces)
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
                visual: .network(
                    label: prefix,
                    download: "—",
                    upload: "—",
                    reservedRate: reservedRate,
                    layout: layout
                ),
                staleStamp: nil,
                severity: .normal
            )
        }
        let download = "↓\(rate(value.downloadBytesPerSecond, decimalPlaces: decimalPlaces))"
        let upload = "↑\(rate(value.uploadBytesPerSecond, decimalPlaces: decimalPlaces))"
        return MetricSegment(
            title: "\(prefix) \(download) \(upload)",
            visual: .network(
                label: prefix,
                download: download,
                upload: upload,
                reservedRate: reservedRate,
                layout: layout
            ),
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
        let reservedValue = percentPlaceholder(decimalPlaces: decimalPlaces)
        guard let value = state.value else {
            return MetricSegment(
                title: "\(prefix) —",
                visual: .metric(
                    label: prefix,
                    value: "—",
                    reservedValue: reservedValue
                ),
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
        let formattedValue = String(
            format: "%.\(decimalPlaces)f%%",
            value.freePercent
        )
        let title = "\(prefix) \(formattedValue)"
        return MetricSegment(
            title: title,
            visual: .metric(
                label: prefix,
                value: formattedValue,
                reservedValue: reservedValue
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
        let scale = decimalPlaces == 0 ? 1.0 : 10.0
        value = (value * scale).rounded() / scale
        if value >= 1_000, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        return String(format: "%.\(decimalPlaces)f%@", value, units[index])
    }

    private static func percentPlaceholder(decimalPlaces: Int) -> String {
        decimalPlaces == 0 ? "100%" : "100.0%"
    }

    private static func temperaturePlaceholder(decimalPlaces: Int) -> String {
        decimalPlaces == 0 ? "100°C" : "100.0°C"
    }

    private static func ratePlaceholder(decimalPlaces: Int) -> String {
        decimalPlaces == 0 ? "↑999M/s" : "↑999.9M/s"
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
    let visual: StatusVisualSegment
    let staleStamp: SampleStamp?
    let severity: MetricVisualSeverity
}

enum StatusItemTitleRenderer {
    private static let imageHeight: CGFloat = 22
    private static let labelValueSpacing: CGFloat = 4
    private static let stackedLineOverlap: CGFloat = 3
    private static let regularFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .medium
    )
    private static let stackedFont = NSFont.monospacedDigitSystemFont(
        ofSize: 9,
        weight: .medium
    )

    static func image(
        segments: [StatusVisualSegment],
        separator: String,
        trailingText: String,
        color: NSColor
    ) -> NSImage {
        let width = contentWidth(
            segments: segments,
            separator: separator,
            trailingText: trailingText
        )
        return NSImage(
            size: NSSize(width: width, height: imageHeight),
            flipped: false
        ) { _ in
            draw(
                segments: segments,
                separator: separator,
                trailingText: trailingText,
                color: color
            )
            return true
        }
    }

    static func contentWidth(
        segments: [StatusVisualSegment],
        separator: String,
        trailingText: String
    ) -> CGFloat {
        let separatorWidth = textSize(separator, font: regularFont).width
        let segmentsWidth = segments.reduce(CGFloat.zero) { partial, segment in
            switch segment {
            case let .metric(label, value, reservedValue):
                return partial + textSize(label, font: regularFont).width
                    + labelValueSpacing
                    + valueSlotWidth(value, reservedValue: reservedValue, font: regularFont)
            case let .network(label, download, upload, reservedRate, layout):
                let font = layout == .horizontal ? regularFont : stackedFont
                let ratesWidth: CGFloat
                if layout == .horizontal {
                    ratesWidth = valueSlotWidth(
                        "\(download) \(upload)",
                        reservedValue: "\(reservedRate) \(reservedRate)",
                        font: font
                    )
                } else {
                    ratesWidth = max(
                        valueSlotWidth(download, reservedValue: reservedRate, font: font),
                        valueSlotWidth(upload, reservedValue: reservedRate, font: font)
                    )
                }
                return partial + textSize(label, font: regularFont).width
                    + labelValueSpacing + ratesWidth
            }
        }
        return segmentsWidth
            + separatorWidth * CGFloat(max(0, segments.count - 1))
            + textSize(trailingText, font: regularFont).width
    }

    private static func draw(
        segments: [StatusVisualSegment],
        separator: String,
        trailingText: String,
        color: NSColor
    ) {
        var x = contentWidth(
            segments: segments,
            separator: separator,
            trailingText: trailingText
        ) - visibleContentWidth(
            segments: segments,
            separator: separator,
            trailingText: trailingText
        )
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                x += drawCentered(separator, atX: x, font: regularFont, color: color)
            }
            switch segment {
            case let .metric(label, value, _):
                x += drawCentered(label, atX: x, font: regularFont, color: color)
                x += labelValueSpacing
                x += drawCentered(value, atX: x, font: regularFont, color: color)
            case let .network(label, download, upload, _, layout):
                x += drawCentered(label, atX: x, font: regularFont, color: color)
                x += labelValueSpacing
                if layout == .horizontal {
                    let rateText = "\(download) \(upload)"
                    x += drawCentered(
                        rateText,
                        atX: x,
                        font: regularFont,
                        color: color
                    )
                } else {
                    let rateWidth = max(
                        textSize(download, font: stackedFont).width,
                        textSize(upload, font: stackedFont).width
                    )
                    drawStacked(
                        top: download,
                        bottom: upload,
                        atX: x,
                        width: rateWidth,
                        color: color
                    )
                    x += rateWidth
                }
            }
        }
        if !trailingText.isEmpty {
            _ = drawCentered(trailingText, atX: x, font: regularFont, color: color)
        }
    }

    static func visibleContentWidth(
        segments: [StatusVisualSegment],
        separator: String,
        trailingText: String
    ) -> CGFloat {
        let separatorWidth = textSize(separator, font: regularFont).width
        let segmentsWidth = segments.reduce(CGFloat.zero) { partial, segment in
            switch segment {
            case let .metric(label, value, _):
                return partial + textSize(label, font: regularFont).width
                    + labelValueSpacing + textSize(value, font: regularFont).width
            case let .network(label, download, upload, _, layout):
                let ratesWidth = layout == .horizontal
                    ? textSize("\(download) \(upload)", font: regularFont).width
                    : max(
                        textSize(download, font: stackedFont).width,
                        textSize(upload, font: stackedFont).width
                    )
                return partial + textSize(label, font: regularFont).width
                    + labelValueSpacing + ratesWidth
            }
        }
        return segmentsWidth
            + separatorWidth * CGFloat(max(0, segments.count - 1))
            + textSize(trailingText, font: regularFont).width
    }

    private static func drawCentered(
        _ text: String,
        atX x: CGFloat,
        font: NSFont,
        color: NSColor
    ) -> CGFloat {
        let size = textSize(text, font: font)
        text.draw(
            at: NSPoint(x: x, y: floor((imageHeight - size.height) / 2)),
            withAttributes: attributes(font: font, color: color)
        )
        return size.width
    }

    private static func drawStacked(
        top: String,
        bottom: String,
        atX x: CGFloat,
        width: CGFloat,
        color: NSColor
    ) {
        let topSize = textSize(top, font: stackedFont)
        let bottomSize = textSize(bottom, font: stackedFont)
        let totalHeight = topSize.height + bottomSize.height - stackedLineOverlap
        let bottomY = floor((imageHeight - totalHeight) / 2)
        let textAttributes = attributes(font: stackedFont, color: color)
        bottom.draw(
            at: NSPoint(x: x + width - bottomSize.width, y: bottomY),
            withAttributes: textAttributes
        )
        top.draw(
            at: NSPoint(
                x: x + width - topSize.width,
                y: bottomY + bottomSize.height - stackedLineOverlap
            ),
            withAttributes: textAttributes
        )
    }

    private static func valueSlotWidth(
        _ value: String,
        reservedValue: String,
        font: NSFont
    ) -> CGFloat {
        max(
            textSize(value, font: font).width,
            textSize(reservedValue, font: font).width
        )
    }

    private static func attributes(
        font: NSFont,
        color: NSColor
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color
        ]
    }

    private static func textSize(_ text: String, font: NSFont) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }
}

private extension Array where Element == StatusVisualSegment {
    func accessibilityText(separator: String, trailingText: String) -> String {
        map { segment in
            switch segment {
            case let .metric(label, value, _): return "\(label) \(value)"
            case let .network(label, download, upload, _, _):
                return "\(label) \(download) \(upload)"
            }
        }.joined(separator: separator) + trailingText
    }
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
