import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let cpuValue = NSTextField(labelWithString: "—")
    private let cpuSummaryValue = NSTextField(labelWithString: "—")
    private let memoryValue = NSTextField(labelWithString: "—")
    private let memorySummaryValue = NSTextField(labelWithString: "—")
    private let batteryValue = NSTextField(labelWithString: "—")
    private let batterySessionMaximumValue = NSTextField(labelWithString: "—")
    private let batteryMaximumValue = NSTextField(labelWithString: "—")
    private let thermalValue = NSTextField(labelWithString: "—")
    private let updatedValue = NSTextField(labelWithString: "—")
    private let cpuSparkline = SparklineView()
    private let memorySparkline = SparklineView()

    private let titleLabel = NSTextField(labelWithString: "Metrilens")
    private let cpuTitle = NSTextField(labelWithString: "CPU")
    private let memoryTitle = NSTextField(labelWithString: "")
    private let batteryTitle = NSTextField(labelWithString: "")
    private let batterySessionMaximumTitle = NSTextField(labelWithString: "")
    private let batteryMaximumTitle = NSTextField(labelWithString: "")
    private let thermalTitle = NSTextField(labelWithString: "")
    private let aboutButton = NSButton()
    private let settingsButton = NSButton()
    private let resetSessionMaximumButton = NSButton()
    private let quitButton = NSButton()

    private let batteryRow = NSStackView()
    private let batterySessionMaximumRow = NSStackView()
    private let batteryMaximumRow = NSStackView()
    private var preferences: PreferencesSnapshot
    private let keyboardFocusHandler: (NSWindow?) -> Void

    var onVisibilityChange: ((Bool) -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onOpenAbout: (() -> Void)?
    var onResetBatterySessionMaximum: (() -> Void)?
    var onQuit: (() -> Void)?

    init(
        preferences: PreferencesSnapshot,
        keyboardFocusHandler: ((NSWindow?) -> Void)? = nil
    ) {
        self.preferences = preferences
        self.keyboardFocusHandler = keyboardFocusHandler ?? { window in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKey()
        }
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        updateContentSize()
        popover.contentViewController = makeContentController()
        applyLocalization()
        applyDisplayPreferences()
    }

    convenience init(
        showsSparkline: Bool,
        keyboardFocusHandler: ((NSWindow?) -> Void)? = nil
    ) {
        self.init(
            preferences: PreferencesSnapshot(
                primaryMetric: .cpu,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: showsSparkline
            ),
            keyboardFocusHandler: keyboardFocusHandler
        )
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
        let language = preferences.language
        cpuValue.stringValue = Self.cpuText(snapshot.cpu, language: language)
        cpuValue.setAccessibilityValue(cpuValue.stringValue)
        cpuValue.textColor = Self.metricTextColor(snapshot.cpu)
        cpuSummaryValue.stringValue = Self.summaryText(
            snapshot.cpuHistorySummary,
            language: language
        )

        memoryValue.stringValue = Self.memoryText(snapshot.memory, language: language)
        memoryValue.setAccessibilityValue(memoryValue.stringValue)
        memoryValue.textColor = Self.metricTextColor(snapshot.memory)
        memorySummaryValue.stringValue = Self.summaryText(
            snapshot.memoryHistorySummary,
            language: language
        )

        updateTemperatureField(batteryValue, state: snapshot.batteryTemperature)
        updateTemperatureField(
            batterySessionMaximumValue,
            state: snapshot.batterySessionMaximumTemperature
        )
        updateTemperatureField(
            batteryMaximumValue,
            state: snapshot.batteryMaximumTemperature
        )
        thermalValue.stringValue = AppText.thermalName(
            snapshot.thermalLevel,
            language: language
        )
        thermalValue.setAccessibilityValue(thermalValue.stringValue)
        thermalValue.textColor = Self.color(
            severity: MetricPresentationPolicy.thermalSeverity(snapshot.thermalLevel)
        )

        let noBattery = Self.isNoHardware(snapshot.batteryTemperature)
        batteryRow.isHidden = false
        batterySessionMaximumRow.isHidden = noBattery
        batteryMaximumRow.isHidden = noBattery
        resetSessionMaximumButton.isEnabled =
            snapshot.batteryTemperature.freshValue != nil
            && snapshot.batterySessionMaximumTemperature.value != nil

        cpuSparkline.points = snapshot.cpuHistory
        cpuSparkline.summary = snapshot.cpuHistorySummary
        cpuSparkline.isCollecting = snapshot.cpuHistoryCollecting
        memorySparkline.points = snapshot.memoryHistory
        memorySparkline.summary = snapshot.memoryHistorySummary
        memorySparkline.isCollecting = snapshot.memoryHistoryCollecting

        let stamps = [
            snapshot.cpu.stamp,
            snapshot.memory.stamp,
            snapshot.batteryTemperature.stamp
        ].compactMap { $0 }
        if let latest = stamps.max(by: { $0.wallTime < $1.wallTime }) {
            updatedValue.stringValue = language.text(
                "更新于 \(Self.timeFormatter.string(from: latest.wallTime))",
                "Updated \(Self.timeFormatter.string(from: latest.wallTime))"
            )
        } else {
            updatedValue.stringValue = language.text("正在收集", "Collecting")
        }
    }

    func setPreferences(_ preferences: PreferencesSnapshot) {
        self.preferences = preferences
        applyLocalization()
        applyDisplayPreferences()
        updateContentSize()
    }

    func setShowsSparkline(_ visible: Bool) {
        var snapshot = preferences
        snapshot = PreferencesSnapshot(
            primaryMetric: snapshot.primaryMetric,
            refreshInterval: snapshot.refreshInterval,
            launchAtLogin: snapshot.launchAtLogin,
            showsSparkline: visible,
            statusDisplayMode: snapshot.statusDisplayMode,
            compactMetrics: snapshot.compactMetrics,
            language: snapshot.language,
            alertsEnabled: snapshot.alertsEnabled,
            cpuAlertThreshold: snapshot.cpuAlertThreshold,
            memoryAlertThreshold: snapshot.memoryAlertThreshold,
            alertSustainDuration: snapshot.alertSustainDuration
        )
        setPreferences(snapshot)
    }

    func popoverDidClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }

    private func makeContentController() -> NSViewController {
        let controller = NSViewController()
        let root = NSView()
        controller.view = root

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        aboutButton.image = NSImage(
            systemSymbolName: "info.circle",
            accessibilityDescription: nil
        )
        aboutButton.target = self
        aboutButton.action = #selector(openAbout)
        aboutButton.isBordered = false
        aboutButton.keyEquivalent = "i"
        aboutButton.keyEquivalentModifierMask = .command

        settingsButton.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: nil
        )
        settingsButton.target = self
        settingsButton.action = #selector(openPreferences)
        settingsButton.isBordered = false
        settingsButton.keyEquivalent = ","
        settingsButton.keyEquivalentModifierMask = .command

        let header = NSStackView(
            views: [titleLabel, NSView(), aboutButton, settingsButton]
        )
        header.orientation = .horizontal
        header.alignment = .centerY

        let cpuRow = makeRow(title: cpuTitle, value: cpuValue)
        configureSummary(cpuSummaryValue)
        configureSparkline(cpuSparkline)

        let memoryRow = makeRow(title: memoryTitle, value: memoryValue)
        configureSummary(memorySummaryValue)
        configureSparkline(memorySparkline)

        configureRow(batteryRow, title: batteryTitle, value: batteryValue)
        resetSessionMaximumButton.target = self
        resetSessionMaximumButton.action = #selector(resetSessionMaximum)
        resetSessionMaximumButton.isBordered = false
        resetSessionMaximumButton.font = .systemFont(ofSize: 10)
        configureRow(
            batterySessionMaximumRow,
            title: batterySessionMaximumTitle,
            value: batterySessionMaximumValue,
            trailing: resetSessionMaximumButton
        )
        configureRow(
            batteryMaximumRow,
            title: batteryMaximumTitle,
            value: batteryMaximumValue
        )
        let thermalRow = makeRow(title: thermalTitle, value: thermalValue)

        updatedValue.textColor = .secondaryLabelColor
        updatedValue.font = .systemFont(ofSize: 11)
        quitButton.target = self
        quitButton.action = #selector(quitApplication)
        quitButton.isBordered = false
        quitButton.font = .systemFont(ofSize: 11)
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = .command
        let footer = NSStackView(views: [updatedValue, NSView(), quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let rows = [
            header,
            separator(),
            cpuRow,
            cpuSummaryValue,
            cpuSparkline,
            memoryRow,
            memorySummaryValue,
            memorySparkline,
            batteryRow,
            batterySessionMaximumRow,
            batteryMaximumRow,
            thermalRow,
            separator(),
            footer
        ]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        for row in [
            header,
            cpuRow,
            cpuSummaryValue,
            cpuSparkline,
            memoryRow,
            memorySummaryValue,
            memorySparkline,
            batteryRow,
            batterySessionMaximumRow,
            batteryMaximumRow,
            thermalRow,
            footer
        ] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        return controller
    }

    private func makeRow(
        title: NSTextField,
        value: NSTextField
    ) -> NSStackView {
        let row = NSStackView()
        configureRow(row, title: title, value: value)
        return row
    }

    private func configureRow(
        _ row: NSStackView,
        title: NSTextField,
        value: NSTextField,
        trailing: NSView? = nil
    ) {
        title.textColor = .secondaryLabelColor
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        var views: [NSView] = [title, NSView(), value]
        if let trailing {
            views.append(trailing)
        }
        row.setViews(views, in: .leading)
        row.orientation = .horizontal
        row.alignment = .centerY
    }

    private func configureSummary(_ field: NSTextField) {
        field.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.alignment = .right
    }

    private func configureSparkline(_ view: SparklineView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func applyLocalization() {
        let language = preferences.language
        titleLabel.stringValue = "Metrilens"
        cpuTitle.stringValue = "CPU"
        memoryTitle.stringValue = language.text("Metrilens 占用", "Metrilens Memory")
        batteryTitle.stringValue = language.text("电池温度", "Battery Temperature")
        batterySessionMaximumTitle.stringValue = language.text(
            "本次最高",
            "Session Maximum"
        )
        batteryMaximumTitle.stringValue = language.text(
            "设备历史最高",
            "Device Maximum"
        )
        thermalTitle.stringValue = language.text("系统热状态", "Thermal State")

        aboutButton.setAccessibilityLabel(
            language.text("关于 Metrilens", "About Metrilens")
        )
        aboutButton.setAccessibilityHelp(
            language.text(
                "打开版本与隐私安全诊断信息",
                "Open version and privacy-safe diagnostics"
            )
        )
        settingsButton.setAccessibilityLabel(language.text("设置", "Settings"))
        settingsButton.setAccessibilityHelp(
            language.text(
                "打开显示、采样与提醒设置",
                "Open display, sampling, and alert settings"
            )
        )
        resetSessionMaximumButton.title = language.text("重置", "Reset")
        resetSessionMaximumButton.setAccessibilityHelp(
            language.text(
                "以当前温度重新开始统计本次最高温度",
                "Restart the session maximum from the current temperature"
            )
        )
        quitButton.title = language.text("退出", "Quit")

        cpuValue.setAccessibilityLabel("CPU")
        memoryValue.setAccessibilityLabel(memoryTitle.stringValue)
        batteryValue.setAccessibilityLabel(batteryTitle.stringValue)
        batterySessionMaximumValue.setAccessibilityLabel(
            batterySessionMaximumTitle.stringValue
        )
        batteryMaximumValue.setAccessibilityLabel(batteryMaximumTitle.stringValue)
        thermalValue.setAccessibilityLabel(thermalTitle.stringValue)

        cpuSparkline.language = language
        cpuSparkline.metricName = "CPU"
        memorySparkline.language = language
        memorySparkline.metricName = language.text("内存", "Memory")
    }

    private func applyDisplayPreferences() {
        cpuSparkline.isHidden = !preferences.showsSparkline
        memorySparkline.isHidden = !preferences.showsSparkline
    }

    private func updateContentSize() {
        popover.contentSize = NSSize(
            width: 360,
            height: preferences.showsSparkline ? 470 : 390
        )
    }

    private func updateTemperatureField(
        _ field: NSTextField,
        state: MetricState<Double>
    ) {
        field.stringValue = Self.temperatureText(
            state,
            language: preferences.language
        )
        field.setAccessibilityValue(field.stringValue)
        field.textColor = Self.temperatureTextColor(state)
    }

    @objc private func openPreferences() {
        popover.performClose(nil)
        onOpenPreferences?()
    }

    @objc private func openAbout() {
        popover.performClose(nil)
        onOpenAbout?()
    }

    @objc private func resetSessionMaximum() {
        onResetBatterySessionMaximum?()
    }

    @objc private func quitApplication() {
        onQuit?()
    }

    private static func cpuText(
        _ state: MetricState<CPUMetric>,
        language: AppLanguage
    ) -> String {
        guard let value = state.value else {
            return placeholder(state, language: language)
        }
        return String(
            format: "%.1f%%%@",
            value.percent,
            state.isStale ? language.text(" · 已过期", " · Stale") : ""
        )
    }

    private static func memoryText(
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
            format: "\(used) / \(total)  %.0f%%%@",
            value.percent,
            state.isStale ? language.text(" · 已过期", " · Stale") : ""
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
            state.isStale ? language.text(" · 已过期", " · Stale") : ""
        )
    }

    private static func summaryText(
        _ summary: MetricHistorySummary?,
        language: AppLanguage
    ) -> String {
        guard let summary else {
            return language.text("平均 — · 峰值 —", "Average — · Peak —")
        }
        return String(
            format: language.text(
                "平均 %.1f%% · 峰值 %.1f%%",
                "Average %.1f%% · Peak %.1f%%"
            ),
            summary.average,
            summary.peak
        )
    }

    private static func placeholder<T>(
        _ state: MetricState<T>,
        language: AppLanguage
    ) -> String {
        switch state {
        case let .unsupported(reason), let .unavailable(reason):
            return AppText.failureReason(reason, language: language)
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

    static func temperatureTextColor(_ state: MetricState<Double>) -> NSColor {
        if state.isStale { return .secondaryLabelColor }
        guard let value = state.value else { return .labelColor }
        return color(
            severity: MetricPresentationPolicy.temperatureSeverity(value)
        )
    }

    private static func color(severity: MetricVisualSeverity) -> NSColor {
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
