import AppKit

final class SparklineView: NSView {
    var accentColor: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var primaryTextColor: NSColor = .labelColor { didSet { needsDisplay = true } }
    var secondaryTextColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var tooltipBackgroundColor: NSColor = .windowBackgroundColor { didSet { needsDisplay = true } }
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
            drawRangeLabel()
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
        let verticalRange = Self.verticalRange(for: points)
        let plotRect = self.plotRect
        for (index, point) in points.enumerated() {
            let x = plotRect.minX
                + CGFloat((point.uptime - start) / span) * plotRect.width
            let normalized = Self.normalizedHeight(
                for: point.percent,
                in: verticalRange
            )
            let y = plotRect.maxY - CGFloat(normalized) * max(1, plotRect.height)
            let location = NSPoint(x: x, y: y)
            index == 0 ? path.move(to: location) : path.line(to: location)
        }

        accentColor.setStroke()
        path.stroke()
    }

    private func drawCollectingLabel() {
        let text = NSAttributedString(
            string: language.localized("Collecting"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: secondaryTextColor
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
        let plotRect = self.plotRect
        let x = plotRect.minX
            + CGFloat((point.uptime - first.uptime) / span) * plotRect.width
        let normalized = Self.normalizedHeight(
            for: point.percent,
            in: Self.verticalRange(for: points)
        )
        let y = plotRect.maxY - CGFloat(normalized) * max(1, plotRect.height)

        accentColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
        ).fill()

        let label = NSAttributedString(
            string: String(format: "%.1f%%", point.percent),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: primaryTextColor,
                .backgroundColor: tooltipBackgroundColor.withAlphaComponent(0.9)
            ]
        )
        let size = label.size()
        let origin = Self.hoverLabelOrigin(
            point: NSPoint(x: x, y: y),
            labelSize: size,
            bounds: bounds
        )
        label.draw(at: origin)
    }

    private var plotRect: NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.minY + 12,
            width: bounds.width,
            height: max(1, bounds.height - 14)
        )
    }

    private func drawRangeLabel() {
        let range = Self.verticalRange(for: points)
        let label = NSAttributedString(
            string: String(
                format: "%.0f–%.0f%%",
                range.lowerBound,
                range.upperBound
            ),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 10,
                    weight: .medium
                ),
                .foregroundColor: secondaryTextColor
            ]
        )
        label.draw(at: NSPoint(x: bounds.minX, y: bounds.minY))
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibility()
    }

    private func updateAccessibility() {
        setAccessibilityLabel(
            language.localized(
                "sparkline.accessibilityLabel",
                arguments: metricName
            )
        )
        guard let current = points.last?.percent else {
            setAccessibilityValue(
                isCollecting
                    ? language.localized("Collecting")
                    : language.localized("No samples")
            )
            return
        }
        let collecting = isCollecting
            ? language.localized(", still collecting")
            : ""
        let displayRange = Self.verticalRange(for: points)
        let rangeText = String(
            format: language.localized(", display range %.0f to %.0f%%"),
            displayRange.lowerBound,
            displayRange.upperBound
        )
        let summaryText: String
        if let summary {
            summaryText = String(
                format: language.localized("sparkline.summaryAccessibility"),
                summary.average,
                summary.peak
            )
        } else {
            summaryText = ""
        }
        setAccessibilityValue(
            String(
                format: language.localized("%d samples, current %.1f%%%@%@"),
                points.count,
                current,
                summaryText + rangeText,
                collecting
            )
        )
    }

    static func hoverLabelOrigin(
        point: NSPoint,
        labelSize: NSSize,
        bounds: NSRect
    ) -> NSPoint {
        let x = min(
            bounds.maxX - labelSize.width,
            max(bounds.minX, point.x - labelSize.width / 2)
        )
        let preferredY = point.y - labelSize.height - 4
        let y = min(
            bounds.maxY - labelSize.height,
            max(bounds.minY + 12, preferredY)
        )
        return NSPoint(x: x, y: y)
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

    static func verticalRange(
        for points: [MetricHistoryPoint]
    ) -> ClosedRange<Double> {
        let percentages = points.compactMap { point -> Double? in
            guard point.percent.isFinite else { return nil }
            return min(100, max(0, point.percent))
        }
        guard let minimum = percentages.min(),
              let maximum = percentages.max() else {
            return 0...100
        }

        // Keep quiet metrics readable without implying movement that was not
        // sampled. Two percentage points still leave enough context around
        // sub-percent memory changes while avoiding an over-zoomed chart.
        let minimumSpan = 2.0
        let observedSpan = maximum - minimum
        let paddedSpan = observedSpan * 1.5
        let span = min(100, max(minimumSpan, paddedSpan))
        let midpoint = (minimum + maximum) / 2
        var lowerBound = midpoint - span / 2
        var upperBound = midpoint + span / 2

        if lowerBound < 0 {
            upperBound -= lowerBound
            lowerBound = 0
        }
        if upperBound > 100 {
            lowerBound -= upperBound - 100
            upperBound = 100
        }

        return max(0, lowerBound)...min(100, upperBound)
    }

    static func normalizedHeight(
        for percent: Double,
        in range: ClosedRange<Double>
    ) -> Double {
        guard percent.isFinite else { return 0 }
        let span = max(1, range.upperBound - range.lowerBound)
        return min(1, max(0, (percent - range.lowerBound) / span))
    }
}
