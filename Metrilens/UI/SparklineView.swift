import AppKit

final class SparklineView: NSView {
    var isCollecting = true {
        didSet {
            updateAccessibility()
            guard oldValue != isCollecting, !isHidden else { return }
            needsDisplay = true
        }
    }

    var points: [CPUHistoryPoint] = [] {
        didSet {
            updateAccessibility()
            guard !isHidden else { return }
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if points.count >= 2 {
            drawLine()
        }
        if isCollecting {
            drawCollectingLabel()
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
            string: "正在收集",
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

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("最近 60 秒 CPU 使用率")
        updateAccessibility()
    }

    private func updateAccessibility() {
        guard let current = points.last?.percent else {
            setAccessibilityValue(isCollecting ? "正在收集" : "暂无样本")
            return
        }
        let collecting = isCollecting ? "，仍在收集" : ""
        setAccessibilityValue(
            String(format: "%d 个样本，当前 %.1f%%%@" , points.count, current, collecting)
        )
    }
}
