import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let cpuValue = NSTextField(labelWithString: "—")
    private let cpuSummaryValue = NSTextField(labelWithString: "—")
    private let memoryValue = NSTextField(labelWithString: "—")
    private let memorySummaryValue = NSTextField(labelWithString: "—")
    private let batteryValue = NSTextField(labelWithString: "—")
    private let batteryLevelValue = NSTextField(labelWithString: "—")
    private let batteryStateValue = NSTextField(labelWithString: "—")
    private let batteryCyclesValue = NSTextField(labelWithString: "—")
    private let batteryHealthValue = NSTextField(labelWithString: "—")
    private let batterySessionMaximumValue = NSTextField(labelWithString: "—")
    private let batteryMaximumValue = NSTextField(labelWithString: "—")
    private let networkDownloadValue = NSTextField(labelWithString: "—")
    private let networkUploadValue = NSTextField(labelWithString: "—")
    private let diskUsageValue = NSTextField(labelWithString: "—")
    private let diskFreeValue = NSTextField(labelWithString: "—")
    private let thermalValue = NSTextField(labelWithString: "—")
    private let heatDiagnosisValue = NSTextField(wrappingLabelWithString: "—")
    private let updatedValue = NSTextField(labelWithString: "—")
    private let contentScrollView = NSScrollView()
    private let cpuSparkline = SparklineView()
    private let memorySparkline = SparklineView()

    private let titleLabel = NSTextField(labelWithString: "Metrilens")
    private let cpuTitle = NSTextField(labelWithString: "CPU")
    private let memoryTitle = NSTextField(labelWithString: "")
    private let batteryTitle = NSTextField(labelWithString: "")
    private let batteryLevelTitle = NSTextField(labelWithString: "")
    private let batteryStateTitle = NSTextField(labelWithString: "")
    private let batteryCyclesTitle = NSTextField(labelWithString: "")
    private let batteryHealthTitle = NSTextField(labelWithString: "")
    private let batterySessionMaximumTitle = NSTextField(labelWithString: "")
    private let batteryMaximumTitle = NSTextField(labelWithString: "")
    private let networkDownloadTitle = NSTextField(labelWithString: "")
    private let networkUploadTitle = NSTextField(labelWithString: "")
    private let diskUsageTitle = NSTextField(labelWithString: "")
    private let diskFreeTitle = NSTextField(labelWithString: "")
    private let thermalTitle = NSTextField(labelWithString: "")
    private let heatDiagnosisTitle = NSTextField(labelWithString: "")
    private let aboutButton = NSButton()
    private let settingsButton = NSButton()
    private let resetSessionMaximumButton = NSButton()
    private let quitButton = NSButton()

    private let batteryRow = NSStackView()
    private let batterySessionMaximumRow = NSStackView()
    private let batteryMaximumRow = NSStackView()
    private let cpuSection = NSStackView()
    private let memorySection = NSStackView()
    private let batterySection = NSStackView()
    private let networkSection = NSStackView()
    private let diskSection = NSStackView()
    private let metricSectionsStack = NSStackView()
    private weak var contentStack: NSStackView?
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

    func layoutStateForTesting() -> (
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        scrollable: Bool
    ) {
        guard let view = popover.contentViewController?.view else {
            return (0, 0, false)
        }
        view.frame = NSRect(origin: .zero, size: popover.contentSize)
        view.layoutSubtreeIfNeeded()
        return (
            contentScrollView.contentView.bounds.height,
            contentStack?.fittingSize.height ?? 0,
            contentScrollView.hasVerticalScroller
        )
    }

    func batteryVisibilityForTesting() -> (
        sectionHidden: Bool,
        temperatureRowsHidden: Bool
    ) {
        (
            batterySection.isHidden,
            batteryRow.isHidden
                && batterySessionMaximumRow.isHidden
                && batteryMaximumRow.isHidden
        )
    }

    func diskPresentationForTesting() -> (
        usedText: String,
        freeText: String,
        usedColor: NSColor,
        freeColor: NSColor
    ) {
        (
            diskUsageValue.stringValue,
            diskFreeValue.stringValue,
            diskUsageValue.textColor ?? .labelColor,
            diskFreeValue.textColor ?? .labelColor
        )
    }

    func networkPresentationForTesting() -> (
        downloadText: String,
        uploadText: String,
        downloadColor: NSColor,
        uploadColor: NSColor
    ) {
        (
            networkDownloadValue.stringValue,
            networkUploadValue.stringValue,
            networkDownloadValue.textColor ?? .labelColor,
            networkUploadValue.textColor ?? .labelColor
        )
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

        updateBatteryDetails(snapshot.battery)
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
        updateNetwork(snapshot.network)
        updateDisk(snapshot.disk)
        updateHeatDiagnosis(HeatDiagnosisAnalyzer.evaluate(snapshot))

        let noBattery = Self.isNoHardware(snapshot.battery)
        let noTemperature =
            noBattery || Self.isNoHardware(snapshot.batteryTemperature)
        batterySection.isHidden = noBattery
        batteryRow.isHidden = noTemperature
        batterySessionMaximumRow.isHidden = noTemperature
        batteryMaximumRow.isHidden = noTemperature
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
            snapshot.batteryTemperature.stamp,
            snapshot.battery.stamp,
            snapshot.network.stamp,
            snapshot.disk.stamp
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
            metricOrder: snapshot.metricOrder,
            statusSeparator: snapshot.statusSeparator,
            statusDecimalPlaces: snapshot.statusDecimalPlaces,
            language: snapshot.language,
            alertsEnabled: snapshot.alertsEnabled,
            cpuAlertEnabled: snapshot.cpuAlertEnabled,
            memoryAlertEnabled: snapshot.memoryAlertEnabled,
            thermalAlertEnabled: snapshot.thermalAlertEnabled,
            batteryLevelAlertEnabled: snapshot.batteryLevelAlertEnabled,
            batteryTemperatureAlertEnabled: snapshot.batteryTemperatureAlertEnabled,
            diskFreeAlertEnabled: snapshot.diskFreeAlertEnabled,
            cpuAlertThreshold: snapshot.cpuAlertThreshold,
            memoryAlertThreshold: snapshot.memoryAlertThreshold,
            batteryLevelAlertThreshold: snapshot.batteryLevelAlertThreshold,
            batteryTemperatureAlertThreshold:
                snapshot.batteryTemperatureAlertThreshold,
            diskFreeAlertThreshold: snapshot.diskFreeAlertThreshold,
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
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false

        contentScrollView.drawsBackground = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.documentView = document
        root.addSubview(contentScrollView)

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
        configureSection(
            cpuSection,
            views: [cpuRow, cpuSummaryValue, cpuSparkline]
        )

        let memoryRow = makeRow(title: memoryTitle, value: memoryValue)
        configureSummary(memorySummaryValue)
        configureSparkline(memorySparkline)
        configureSection(
            memorySection,
            views: [memoryRow, memorySummaryValue, memorySparkline]
        )

        let batteryLevelRow = makeRow(
            title: batteryLevelTitle,
            value: batteryLevelValue
        )
        let batteryStateRow = makeRow(
            title: batteryStateTitle,
            value: batteryStateValue
        )
        let batteryCyclesRow = makeRow(
            title: batteryCyclesTitle,
            value: batteryCyclesValue
        )
        let batteryHealthRow = makeRow(
            title: batteryHealthTitle,
            value: batteryHealthValue
        )
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
        configureSection(
            batterySection,
            views: [
                batteryLevelRow,
                batteryStateRow,
                batteryCyclesRow,
                batteryHealthRow,
                batteryRow,
                batterySessionMaximumRow,
                batteryMaximumRow
            ]
        )
        let networkDownloadRow = makeRow(
            title: networkDownloadTitle,
            value: networkDownloadValue
        )
        let networkUploadRow = makeRow(
            title: networkUploadTitle,
            value: networkUploadValue
        )
        configureSection(
            networkSection,
            views: [networkDownloadRow, networkUploadRow]
        )
        let diskUsageRow = makeRow(
            title: diskUsageTitle,
            value: diskUsageValue
        )
        let diskFreeRow = makeRow(
            title: diskFreeTitle,
            value: diskFreeValue
        )
        configureSection(diskSection, views: [diskUsageRow, diskFreeRow])

        metricSectionsStack.orientation = .vertical
        metricSectionsStack.alignment = .width
        metricSectionsStack.spacing = 12
        let thermalRow = makeRow(title: thermalTitle, value: thermalValue)
        heatDiagnosisTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        heatDiagnosisValue.textColor = .secondaryLabelColor
        heatDiagnosisValue.font = .systemFont(ofSize: 11)

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
            metricSectionsStack,
            separator(),
            thermalRow,
            heatDiagnosisTitle,
            heatDiagnosisValue,
            separator(),
            footer
        ]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        contentStack = stack

        NSLayoutConstraint.activate([
            contentScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentScrollView.topAnchor.constraint(equalTo: root.topAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: contentScrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: contentScrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: contentScrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        for row in [
            header,
            metricSectionsStack,
            thermalRow,
            heatDiagnosisTitle,
            heatDiagnosisValue,
            footer
        ] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        return controller
    }

    private func configureSection(
        _ section: NSStackView,
        views: [NSView]
    ) {
        section.setViews(views, in: .top)
        section.orientation = .vertical
        section.alignment = .width
        section.spacing = 6
        for view in views {
            view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
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
        batteryLevelTitle.stringValue = language.text("电池电量", "Battery Level")
        batteryStateTitle.stringValue = language.text("供电状态", "Power State")
        batteryCyclesTitle.stringValue = language.text("循环次数", "Cycle Count")
        batteryHealthTitle.stringValue = language.text("电池健康", "Battery Health")
        batterySessionMaximumTitle.stringValue = language.text(
            "本次最高",
            "Session Maximum"
        )
        batteryMaximumTitle.stringValue = language.text(
            "设备历史最高",
            "Device Maximum"
        )
        thermalTitle.stringValue = language.text("系统热状态", "Thermal State")
        networkDownloadTitle.stringValue = language.text("网络下载", "Network Download")
        networkUploadTitle.stringValue = language.text("网络上传", "Network Upload")
        diskUsageTitle.stringValue = language.text("启动磁盘已用", "Startup Disk Used")
        diskFreeTitle.stringValue = language.text("启动磁盘可用", "Startup Disk Available")
        heatDiagnosisTitle.stringValue = language.text(
            "异常发热诊断",
            "Abnormal Heat Diagnosis"
        )

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
        batteryLevelValue.setAccessibilityLabel(batteryLevelTitle.stringValue)
        batteryStateValue.setAccessibilityLabel(batteryStateTitle.stringValue)
        batteryCyclesValue.setAccessibilityLabel(batteryCyclesTitle.stringValue)
        batteryHealthValue.setAccessibilityLabel(batteryHealthTitle.stringValue)
        networkDownloadValue.setAccessibilityLabel(networkDownloadTitle.stringValue)
        networkUploadValue.setAccessibilityLabel(networkUploadTitle.stringValue)
        diskUsageValue.setAccessibilityLabel(diskUsageTitle.stringValue)
        diskFreeValue.setAccessibilityLabel(diskFreeTitle.stringValue)
        heatDiagnosisValue.setAccessibilityLabel(heatDiagnosisTitle.stringValue)

        cpuSparkline.language = language
        cpuSparkline.metricName = "CPU"
        memorySparkline.language = language
        memorySparkline.metricName = language.text("内存", "Memory")
    }

    private func applyDisplayPreferences() {
        cpuSparkline.isHidden = !preferences.showsSparkline
        memorySparkline.isHidden = !preferences.showsSparkline
        let sections: [PrimaryMetric: NSStackView] = [
            .cpu: cpuSection,
            .memory: memorySection,
            .battery: batterySection,
            .network: networkSection,
            .disk: diskSection
        ]
        metricSectionsStack.setViews(
            preferences.metricOrder.compactMap { sections[$0] },
            in: .top
        )
    }

    private func updateContentSize() {
        popover.contentSize = NSSize(
            width: 360,
            height: preferences.showsSparkline ? 650 : 570
        )
    }

    private func updateBatteryDetails(
        _ state: MetricState<BatteryMetric>
    ) {
        guard let metric = state.value else {
            let text = Self.placeholder(state, language: preferences.language)
            for field in [
                batteryLevelValue,
                batteryStateValue,
                batteryCyclesValue,
                batteryHealthValue
            ] {
                field.stringValue = text
                field.textColor = Self.metricTextColor(state)
            }
            return
        }
        batteryLevelValue.stringValue = String(format: "%.0f%%", metric.levelPercent)
        batteryStateValue.stringValue = Self.batteryPowerText(
            metric.powerState,
            language: preferences.language
        )
        batteryCyclesValue.stringValue = metric.cycleCount.map(String.init) ?? "—"
        batteryHealthValue.stringValue = Self.batteryHealthText(
            metric.health,
            language: preferences.language
        )
        for field in [
            batteryLevelValue,
            batteryStateValue,
            batteryCyclesValue,
            batteryHealthValue
        ] {
            field.textColor = state.isStale ? .secondaryLabelColor : .labelColor
        }
    }

    private func updateNetwork(_ state: MetricState<NetworkMetric>) {
        guard let metric = state.value else {
            let text = Self.placeholder(state, language: preferences.language)
            networkDownloadValue.stringValue = text
            networkUploadValue.stringValue = text
            networkDownloadValue.textColor = Self.metricTextColor(state)
            networkUploadValue.textColor = Self.metricTextColor(state)
            return
        }
        networkDownloadValue.stringValue = Self.rateText(
            metric.downloadBytesPerSecond
        )
        networkUploadValue.stringValue = Self.rateText(metric.uploadBytesPerSecond)
        networkDownloadValue.textColor = Self.metricTextColor(state)
        networkUploadValue.textColor = Self.metricTextColor(state)
    }

    private func updateDisk(_ state: MetricState<DiskCapacityMetric>) {
        guard let metric = state.value else {
            let text = Self.placeholder(state, language: preferences.language)
            diskUsageValue.stringValue = text
            diskFreeValue.stringValue = text
            diskUsageValue.textColor = Self.metricTextColor(state)
            diskFreeValue.textColor = Self.metricTextColor(state)
            return
        }
        diskUsageValue.stringValue = "\(Self.byteText(metric.usedBytes))  "
            + String(format: "%.0f%%", metric.usedPercent)
        diskFreeValue.stringValue = "\(Self.byteText(metric.availableBytes))  "
            + String(format: "%.0f%%", metric.freePercent)
        let severity: MetricVisualSeverity =
            metric.freePercent <= 5 ? .warning
            : metric.freePercent <= 10 ? .caution
            : .normal
        diskUsageValue.textColor = Self.metricTextColor(state)
        diskFreeValue.textColor = state.isStale
            ? .secondaryLabelColor
            : Self.color(severity: severity)
    }

    private func updateHeatDiagnosis(_ diagnosis: HeatDiagnosis) {
        let language = preferences.language
        var lines = [HeatDiagnosisAnalyzer.summary(diagnosis, language: language)]
        if diagnosis.isAbnormal {
            lines.append(contentsOf: diagnosis.evidence.map {
                "• " + HeatDiagnosisAnalyzer.evidenceText($0, language: language)
            })
            lines.append(contentsOf: diagnosis.recommendations.prefix(3).map {
                "→ " + HeatDiagnosisAnalyzer.recommendationText(
                    $0,
                    language: language
                )
            })
            lines.append(
                language.text(
                    "Metrilens 不扫描进程；具体来源请在“活动监视器”确认。",
                    "Metrilens does not scan processes; confirm the source in Activity Monitor."
                )
            )
        }
        heatDiagnosisValue.stringValue = lines.joined(separator: "\n")
        heatDiagnosisValue.textColor = diagnosis.severity == .urgent
            ? .systemRed
            : diagnosis.severity == .elevated
                ? .systemOrange
                : .secondaryLabelColor
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

    private static func batteryPowerText(
        _ state: BatteryPowerState,
        language: AppLanguage
    ) -> String {
        switch state {
        case .charging: return language.text("充电中", "Charging")
        case .charged: return language.text("已充满", "Charged")
        case .discharging: return language.text("使用电池", "On Battery")
        case .externalPower: return language.text("外接电源", "Power Adapter")
        case .unknown: return language.text("未知", "Unknown")
        }
    }

    private static func batteryHealthText(
        _ health: BatteryHealth,
        language: AppLanguage
    ) -> String {
        switch health {
        case .good: return language.text("正常", "Good")
        case .fair: return language.text("一般", "Fair")
        case .poor: return language.text("较差", "Poor")
        case .serviceRecommended:
            return language.text("建议维修", "Service Recommended")
        case .unknown: return language.text("系统未提供", "Not Provided")
        }
    }

    private static func rateText(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1_000, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        return String(format: value < 10 && index > 0 ? "%.1f %@" : "%.0f %@", value, units[index])
    }

    private static func byteText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(min(bytes, UInt64(Int64.max))),
            countStyle: .file
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

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
