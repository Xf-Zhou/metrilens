import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let cpuValue = NSTextField(labelWithString: "—")
    private let memoryValue = NSTextField(labelWithString: "—")
    private let batteryValue = NSTextField(labelWithString: "—")
    private let batteryMaximumValue = NSTextField(labelWithString: "—")
    private let thermalValue = NSTextField(labelWithString: "正常")
    private let updatedValue = NSTextField(labelWithString: "尚未采样")
    private let sparkline = SparklineView()
    private let batteryRow = NSStackView()
    private let batteryMaximumRow = NSStackView()
    private var showsSparkline: Bool
    private let keyboardFocusHandler: (NSWindow?) -> Void

    var onVisibilityChange: ((Bool) -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onOpenAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    init(
        showsSparkline: Bool,
        keyboardFocusHandler: ((NSWindow?) -> Void)? = nil
    ) {
        self.showsSparkline = showsSparkline
        self.keyboardFocusHandler = keyboardFocusHandler ?? { window in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKey()
        }
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 330)
        popover.contentViewController = makeContentController()
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            focusKeyboardInput()
            onVisibilityChange?(true)
        }
    }

    func focusKeyboardInput() {
        keyboardFocusHandler(popover.contentViewController?.view.window)
    }

    func update(snapshot: SystemSnapshot) {
        cpuValue.stringValue = Self.cpuText(snapshot.cpu)
        cpuValue.setAccessibilityValue(cpuValue.stringValue)
        cpuValue.textColor = Self.metricTextColor(snapshot.cpu)
        memoryValue.stringValue = Self.memoryText(snapshot.memory)
        memoryValue.setAccessibilityValue(memoryValue.stringValue)
        memoryValue.textColor = Self.metricTextColor(snapshot.memory)
        batteryValue.stringValue = Self.temperatureText(snapshot.batteryTemperature)
        batteryValue.setAccessibilityValue(batteryValue.stringValue)
        batteryValue.textColor = Self.metricTextColor(snapshot.batteryTemperature)
        batteryMaximumValue.stringValue = Self.temperatureText(snapshot.batteryMaximumTemperature)
        batteryMaximumValue.setAccessibilityValue(batteryMaximumValue.stringValue)
        batteryMaximumValue.textColor = Self.metricTextColor(snapshot.batteryMaximumTemperature)
        thermalValue.stringValue = Self.thermalText(snapshot.thermalLevel)
        thermalValue.setAccessibilityValue(thermalValue.stringValue)
        thermalValue.textColor = Self.thermalColor(snapshot.thermalLevel)

        let batteryUnsupported = Self.isNoHardware(snapshot.batteryTemperature)
            && Self.isNoHardware(snapshot.batteryMaximumTemperature)
        batteryRow.isHidden = batteryUnsupported
        batteryMaximumRow.isHidden = batteryUnsupported

        sparkline.isHidden = !showsSparkline
        sparkline.points = snapshot.cpuHistory
        sparkline.isCollecting = snapshot.cpuHistoryCollecting
        let stamps = [
            snapshot.cpu.stamp,
            snapshot.memory.stamp,
            snapshot.batteryTemperature.stamp
        ].compactMap { $0 }
        if let latest = stamps.max(by: { $0.wallTime < $1.wallTime }) {
            updatedValue.stringValue = "更新于 \(Self.timeFormatter.string(from: latest.wallTime))"
        } else {
            updatedValue.stringValue = "正在收集"
        }
    }

    func setShowsSparkline(_ visible: Bool) {
        showsSparkline = visible
        sparkline.isHidden = !visible
    }

    func popoverDidClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }

    private func makeContentController() -> NSViewController {
        let controller = NSViewController()
        let root = NSView()
        controller.view = root

        let title = NSTextField(labelWithString: "Metrilens")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let about = NSButton(
            image: NSImage(
                systemSymbolName: "info.circle",
                accessibilityDescription: "关于 Metrilens"
            ) ?? NSImage(),
            target: self,
            action: #selector(openAbout)
        )
        about.isBordered = false
        about.keyEquivalent = "i"
        about.keyEquivalentModifierMask = .command
        about.setAccessibilityHelp("打开版本与隐私安全诊断信息")
        let settings = NSButton(
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置") ?? NSImage(),
            target: self,
            action: #selector(openPreferences)
        )
        settings.isBordered = false
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        settings.setAccessibilityHelp("打开刷新频率与显示设置")
        let header = NSStackView(views: [title, NSView(), about, settings])
        header.orientation = .horizontal
        header.alignment = .centerY

        let cpuRow = makeRow(title: "CPU", value: cpuValue)
        sparkline.translatesAutoresizingMaskIntoConstraints = false
        sparkline.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let memoryRow = makeRow(title: "Metrilens 占用", value: memoryValue)
        configureRow(batteryRow, title: "电池温度", value: batteryValue)
        configureRow(batteryMaximumRow, title: "电池历史最高", value: batteryMaximumValue)
        let thermalRow = makeRow(title: "系统热状态", value: thermalValue)

        updatedValue.textColor = .secondaryLabelColor
        updatedValue.font = .systemFont(ofSize: 11)
        let quit = NSButton(title: "退出", target: self, action: #selector(quitApplication))
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 11)
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        let footer = NSStackView(views: [updatedValue, NSView(), quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let stack = NSStackView(views: [
            header,
            separator(),
            cpuRow,
            sparkline,
            memoryRow,
            batteryRow,
            batteryMaximumRow,
            thermalRow,
            separator(),
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            cpuRow.widthAnchor.constraint(equalTo: header.widthAnchor),
            sparkline.widthAnchor.constraint(equalTo: header.widthAnchor),
            memoryRow.widthAnchor.constraint(equalTo: header.widthAnchor),
            batteryRow.widthAnchor.constraint(equalTo: header.widthAnchor),
            batteryMaximumRow.widthAnchor.constraint(equalTo: header.widthAnchor),
            thermalRow.widthAnchor.constraint(equalTo: header.widthAnchor),
            footer.widthAnchor.constraint(equalTo: header.widthAnchor)
        ])
        return controller
    }

    private func makeRow(title: String, value: NSTextField) -> NSStackView {
        let row = NSStackView()
        configureRow(row, title: title, value: value)
        return row
    }

    private func configureRow(_ row: NSStackView, title: String, value: NSTextField) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.textColor = .secondaryLabelColor
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        value.setAccessibilityLabel(title)
        value.setAccessibilityValue(value.stringValue)
        row.setViews([titleLabel, NSView(), value], in: .leading)
        row.orientation = .horizontal
        row.alignment = .centerY
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func openPreferences() {
        popover.performClose(nil)
        onOpenPreferences?()
    }

    @objc private func openAbout() {
        popover.performClose(nil)
        onOpenAbout?()
    }

    @objc private func quitApplication() {
        onQuit?()
    }

    private static func cpuText(_ state: MetricState<CPUMetric>) -> String {
        guard let value = state.value else { return placeholder(state) }
        return String(format: "%.1f%%%@", value.percent, state.isStale ? " · 已过期" : "")
    }

    private static func memoryText(_ state: MetricState<MemoryMetric>) -> String {
        guard let value = state.value else { return placeholder(state) }
        let used = ByteCountFormatter.string(fromByteCount: Int64(value.usedBytes), countStyle: .memory)
        let total = ByteCountFormatter.string(fromByteCount: Int64(value.totalBytes), countStyle: .memory)
        return String(format: "\(used) / \(total)  %.0f%%%@", value.percent, state.isStale ? " · 已过期" : "")
    }

    private static func temperatureText(_ state: MetricState<Double>) -> String {
        guard let value = state.value else { return placeholder(state) }
        return String(format: "%.1f°C%@", value, state.isStale ? " · 已过期" : "")
    }

    private static func placeholder<T>(_ state: MetricState<T>) -> String {
        switch state {
        case let .unsupported(reason):
            return reason == .noHardware ? "无电池" : "不支持"
        case .unavailable:
            return "—"
        case .available, .stale:
            return "—"
        }
    }

    private static func isNoHardware<T>(_ state: MetricState<T>) -> Bool {
        if case .unsupported(.noHardware) = state { return true }
        return false
    }

    static func metricTextColor<T>(_ state: MetricState<T>) -> NSColor {
        state.isStale ? .secondaryLabelColor : .labelColor
    }

    private static func thermalText(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "严重"
        case .critical: return "危急"
        }
    }

    private static func thermalColor(_ level: ThermalLevel) -> NSColor {
        switch level {
        case .nominal: return .labelColor
        case .fair: return .systemYellow
        case .serious: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
