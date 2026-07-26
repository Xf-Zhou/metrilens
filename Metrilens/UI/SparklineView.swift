import AppKit

final class SparklineView: NSView {
    var language: AppLanguage = .system {
        didSet {
            updateAccessibility()
            needsDisplay = true
        }
    }

    var metricName = "CPU" {
        didSet {
            updateAccessibility()
            needsDisplay = true
        }
    }

    var isCollecting = true {
        didSet {
            updateAccessibility()
            guard oldValue != isCollecting, !isHidden else { return }
            needsDisplay = true
        }
    }

    var points: [MetricHistoryPoint] = [] {
        didSet {
            hoveredPoint = nil
            updateAccessibility()
            guard !isHidden else { return }
            needsDisplay = true
        }
    }

    var summary: MetricHistorySummary? {
        didSet { updateAccessibility() }
    }

    private var hoveredPoint: MetricHistoryPoint?
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let normalizedX = bounds.width > 0
            ? min(1, max(0, (location.x - bounds.minX) / bounds.width))
            : 0
        hoveredPoint = Self.nearestPoint(
            toNormalizedX: normalizedX,
            points: points
        )
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredPoint = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if points.count >= 2 {
            drawLine()
        }
        if isCollecting {
            drawCollectingLabel()
        }
        if let hoveredPoint {
            drawHoverValue(hoveredPoint)
        }
    }

    private func drawLine() {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        let start = points.first?.uptime ?? 0
        let end = points.last?.uptime ?? start + 1
        let span = max(1, end - start)
        for (index, point) in points.enumerated() {
            let x = bounds.minX + CGFloat((point.uptime - start) / span) * bounds.width
            let normalized = min(1, max(0, point.percent / 100))
            let y = bounds.maxY - CGFloat(normalized) * max(1, bounds.height - 2) - 1
            let location = NSPoint(x: x, y: y)
            index == 0 ? path.move(to: location) : path.line(to: location)
        }

        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    private func drawCollectingLabel() {
        let text = NSAttributedString(
            string: language.text("正在收集", "Collecting"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        let size = text.size()
        text.draw(
            at: NSPoint(
                x: bounds.maxX - size.width,
                y: bounds.minY
            )
        )
    }

    private func drawHoverValue(_ point: MetricHistoryPoint) {
        guard let first = points.first, let last = points.last else { return }
        let span = max(1, last.uptime - first.uptime)
        let x = bounds.minX + CGFloat((point.uptime - first.uptime) / span) * bounds.width
        let normalized = min(1, max(0, point.percent / 100))
        let y = bounds.maxY - CGFloat(normalized) * max(1, bounds.height - 2) - 1

        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
        ).fill()

        let label = NSAttributedString(
            string: String(format: "%.1f%%", point.percent),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.9)
            ]
        )
        let size = label.size()
        let labelX = min(
            bounds.maxX - size.width,
            max(bounds.minX, x - size.width / 2)
        )
        label.draw(at: NSPoint(x: labelX, y: bounds.minY))
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibility()
    }

    private func updateAccessibility() {
        setAccessibilityLabel(
            language.text(
                "最近 60 秒\(metricName)使用率",
                "\(metricName) usage over the last 60 seconds"
            )
        )
        guard let current = points.last?.percent else {
            setAccessibilityValue(
                isCollecting
                    ? language.text("正在收集", "Collecting")
                    : language.text("暂无样本", "No samples")
            )
            return
        }
        let collecting = isCollecting
            ? language.text("，仍在收集", ", still collecting")
            : ""
        let summaryText: String
        if let summary {
            summaryText = String(
                format: language.text(
                    "，平均 %.1f%%，峰值 %.1f%%",
                    ", average %.1f%%, peak %.1f%%"
                ),
                summary.average,
                summary.peak
            )
        } else {
            summaryText = ""
        }
        setAccessibilityValue(
            String(
                format: language.text(
                    "%d 个样本，当前 %.1f%%%@%@",
                    "%d samples, current %.1f%%%@%@"
                ),
                points.count,
                current,
                summaryText,
                collecting
            )
        )
    }

    static func nearestPoint(
        toNormalizedX normalizedX: CGFloat,
        points: [MetricHistoryPoint]
    ) -> MetricHistoryPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        let target = first.uptime
            + TimeInterval(min(1, max(0, normalizedX))) * max(1, last.uptime - first.uptime)
        return points.min {
            abs($0.uptime - target) < abs($1.uptime - target)
        }
    }
}
