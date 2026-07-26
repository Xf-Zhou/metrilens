import AppKit

final class PreferencesController: NSWindowController {
    static let sourceInformation =
        "温度说明：只读取 AppleSmartBattery 电池温度，并区分可重置的本次最高与设备历史最高。"
        + "CPU/GPU 精确温度不在当前范围内。\n\n"
        + "内存说明：“Metrilens 占用”由 internal、wired 与 compressor 内存组成；"
        + "这是稳定的产品口径，不承诺与活动监视器完全一致。"

    private let preferences: AppPreferences
    private let loginItemController: LoginItemController

    private let languagePopup = NSPopUpButton()
    private let displayModePopup = NSPopUpButton()
    private let metricPopup = NSPopUpButton()
    private let metricOrderPopup = NSPopUpButton()
    private let separatorPopup = NSPopUpButton()
    private let precisionPopup = NSPopUpButton()
    private let intervalPopup = NSPopUpButton()
    private let cpuThresholdPopup = NSPopUpButton()
    private let memoryThresholdPopup = NSPopUpButton()
    private let alertDurationPopup = NSPopUpButton()
    private let batteryLevelThresholdPopup = NSPopUpButton()
    private let batteryTemperatureThresholdPopup = NSPopUpButton()
    private let diskFreeThresholdPopup = NSPopUpButton()
    private let loginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let sparklineCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let alertsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let compactCPUCheckbox = NSButton(checkboxWithTitle: "CPU", target: nil, action: nil)
    private let compactMemoryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let compactBatteryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let compactNetworkCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let compactDiskCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let cpuAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let memoryAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let thermalAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let batteryLevelAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let batteryTemperatureAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let diskFreeAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let moveMetricUpButton = NSButton()
    private let moveMetricDownButton = NSButton()
    private let testNotificationButton = NSButton()
    private let notificationSettingsButton = NSButton()
    private let notificationStatusValue = NSTextField(labelWithString: "—")
    private let resetButton = NSButton()
    private let sourceInfo = NSTextField(wrappingLabelWithString: "")

    private let displaySectionTitle = NSTextField(labelWithString: "")
    private let samplingSectionTitle = NSTextField(labelWithString: "")
    private let alertsSectionTitle = NSTextField(labelWithString: "")
    private let systemSectionTitle = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let displayModeLabel = NSTextField(labelWithString: "")
    private let metricLabel = NSTextField(labelWithString: "")
    private let compactMetricsLabel = NSTextField(labelWithString: "")
    private let metricOrderLabel = NSTextField(labelWithString: "")
    private let separatorLabel = NSTextField(labelWithString: "")
    private let precisionLabel = NSTextField(labelWithString: "")
    private let intervalLabel = NSTextField(labelWithString: "")
    private let cpuThresholdLabel = NSTextField(labelWithString: "")
    private let memoryThresholdLabel = NSTextField(labelWithString: "")
    private let alertDurationLabel = NSTextField(labelWithString: "")
    private let batteryLevelThresholdLabel = NSTextField(labelWithString: "")
    private let batteryTemperatureThresholdLabel = NSTextField(labelWithString: "")
    private let diskFreeThresholdLabel = NSTextField(labelWithString: "")
    private let notificationStatusLabel = NSTextField(labelWithString: "")

    private var currentSnapshot: PreferencesSnapshot
    private var notificationAuthorizationState: NotificationAuthorizationState = .unknown
    private weak var contentScrollView: NSScrollView?
    private weak var contentDocumentView: NSView?

    var onTestNotification: (() -> Void)?
    var onOpenNotificationSettings: (() -> Void)?
    var onRefreshNotificationStatus: (() -> Void)?

    init(preferences: AppPreferences, loginItemController: LoginItemController) {
        self.preferences = preferences
        self.loginItemController = loginItemController
        currentSnapshot = preferences.snapshot
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 760),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        super.init(window: window)
        buildContent()
        setPreferences(currentSnapshot)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        setPreferences(preferences.snapshot)
        onRefreshNotificationStatus?()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setNotificationAuthorizationState(
        _ state: NotificationAuthorizationState
    ) {
        notificationAuthorizationState = state
        applyNotificationStatus()
    }

    func setPreferences(_ snapshot: PreferencesSnapshot) {
        currentSnapshot = snapshot
        applyLocalization()
        refresh()
    }

    func initialScrollStateForTesting() -> (
        documentIsFlipped: Bool,
        visibleMinY: CGFloat,
        languageControlVisible: Bool
    ) {
        window?.contentView?.layoutSubtreeIfNeeded()
        guard let document = contentDocumentView,
              let scrollView = contentScrollView else {
            return (false, -1, false)
        }
        let languageFrame = languagePopup.convert(
            languagePopup.bounds,
            to: document
        )
        return (
            document.isFlipped,
            scrollView.documentVisibleRect.minY,
            scrollView.documentVisibleRect.intersects(languageFrame)
        )
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        configurePopup(languagePopup, action: #selector(languageChanged))
        configurePopup(displayModePopup, action: #selector(displayModeChanged))
        configurePopup(metricPopup, action: #selector(metricChanged))
        configurePopup(metricOrderPopup, action: #selector(metricOrderSelectionChanged))
        configurePopup(separatorPopup, action: #selector(separatorChanged))
        configurePopup(precisionPopup, action: #selector(precisionChanged))
        configurePopup(intervalPopup, action: #selector(intervalChanged))
        configurePopup(cpuThresholdPopup, action: #selector(cpuThresholdChanged))
        configurePopup(memoryThresholdPopup, action: #selector(memoryThresholdChanged))
        configurePopup(alertDurationPopup, action: #selector(alertDurationChanged))
        configurePopup(
            batteryLevelThresholdPopup,
            action: #selector(batteryLevelThresholdChanged)
        )
        configurePopup(
            batteryTemperatureThresholdPopup,
            action: #selector(batteryTemperatureThresholdChanged)
        )
        configurePopup(
            diskFreeThresholdPopup,
            action: #selector(diskFreeThresholdChanged)
        )

        configureCheckbox(loginCheckbox, action: #selector(loginChanged))
        configureCheckbox(sparklineCheckbox, action: #selector(sparklineChanged))
        configureCheckbox(alertsCheckbox, action: #selector(alertsChanged))
        for checkbox in [
            compactCPUCheckbox,
            compactMemoryCheckbox,
            compactBatteryCheckbox,
            compactNetworkCheckbox,
            compactDiskCheckbox
        ] {
            configureCheckbox(checkbox, action: #selector(compactMetricsChanged))
        }
        let alertCheckboxes: [(NSButton, MetricAlertKind)] = [
            (cpuAlertCheckbox, .cpu),
            (memoryAlertCheckbox, .memory),
            (thermalAlertCheckbox, .thermal),
            (batteryLevelAlertCheckbox, .batteryLevel),
            (batteryTemperatureAlertCheckbox, .batteryTemperature),
            (diskFreeAlertCheckbox, .diskFree)
        ]
        for (checkbox, kind) in alertCheckboxes {
            checkbox.tag = Self.alertTag(kind)
            configureCheckbox(checkbox, action: #selector(alertKindChanged(_:)))
        }

        moveMetricUpButton.target = self
        moveMetricUpButton.action = #selector(moveMetricUp)
        moveMetricDownButton.target = self
        moveMetricDownButton.action = #selector(moveMetricDown)
        testNotificationButton.target = self
        testNotificationButton.action = #selector(testNotification)
        notificationSettingsButton.target = self
        notificationSettingsButton.action = #selector(openNotificationSettings)

        resetButton.target = self
        resetButton.action = #selector(confirmReset)
        sourceInfo.textColor = .secondaryLabelColor

        let compactControls = NSStackView(
            views: [
                compactCPUCheckbox,
                compactMemoryCheckbox,
                compactBatteryCheckbox,
                compactNetworkCheckbox,
                compactDiskCheckbox
            ]
        )
        compactControls.orientation = .horizontal
        compactControls.spacing = 8
        let orderControls = NSStackView(
            views: [metricOrderPopup, moveMetricUpButton, moveMetricDownButton]
        )
        orderControls.orientation = .horizontal
        orderControls.spacing = 6
        let notificationControls = NSStackView(
            views: [testNotificationButton, notificationSettingsButton]
        )
        notificationControls.orientation = .horizontal
        notificationControls.spacing = 8

        let stack = NSStackView(views: [
            displaySectionTitle,
            settingRow(languageLabel, control: languagePopup),
            settingRow(displayModeLabel, control: displayModePopup),
            settingRow(metricLabel, control: metricPopup),
            settingRow(compactMetricsLabel, control: compactControls),
            settingRow(metricOrderLabel, control: orderControls),
            settingRow(separatorLabel, control: separatorPopup),
            settingRow(precisionLabel, control: precisionPopup),
            separator(),
            samplingSectionTitle,
            settingRow(intervalLabel, control: intervalPopup),
            sparklineCheckbox,
            separator(),
            alertsSectionTitle,
            alertsCheckbox,
            cpuAlertCheckbox,
            settingRow(cpuThresholdLabel, control: cpuThresholdPopup),
            memoryAlertCheckbox,
            settingRow(memoryThresholdLabel, control: memoryThresholdPopup),
            thermalAlertCheckbox,
            batteryLevelAlertCheckbox,
            settingRow(
                batteryLevelThresholdLabel,
                control: batteryLevelThresholdPopup
            ),
            batteryTemperatureAlertCheckbox,
            settingRow(
                batteryTemperatureThresholdLabel,
                control: batteryTemperatureThresholdPopup
            ),
            diskFreeAlertCheckbox,
            settingRow(diskFreeThresholdLabel, control: diskFreeThresholdPopup),
            settingRow(alertDurationLabel, control: alertDurationPopup),
            settingRow(notificationStatusLabel, control: notificationStatusValue),
            notificationControls,
            separator(),
            systemSectionTitle,
            loginCheckbox,
            sourceInfo,
            resetButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let documentView = PreferencesDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView = scrollView
        contentDocumentView = documentView
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            sourceInfo.widthAnchor.constraint(equalToConstant: 492)
        ])
        window?.initialFirstResponder = languagePopup
    }

    private func configurePopup(_ popup: NSPopUpButton, action: Selector) {
        popup.target = self
        popup.action = action
    }

    private func configureCheckbox(_ checkbox: NSButton, action: Selector) {
        checkbox.target = self
        checkbox.action = action
    }

    private func applyLocalization() {
        let language = currentSnapshot.language
        window?.title = language.text("Metrilens 设置", "Metrilens Settings")
        displaySectionTitle.stringValue = language.text("菜单栏显示", "Menu Bar")
        samplingSectionTitle.stringValue = language.text("采样与图表", "Sampling & Charts")
        alertsSectionTitle.stringValue = language.text("本地提醒", "Local Alerts")
        systemSectionTitle.stringValue = language.text("系统与说明", "System & Notes")
        for title in [
            displaySectionTitle,
            samplingSectionTitle,
            alertsSectionTitle,
            systemSectionTitle
        ] {
            title.font = .systemFont(ofSize: 13, weight: .semibold)
        }

        languageLabel.stringValue = language.text("界面语言", "Language")
        displayModeLabel.stringValue = language.text("显示模式", "Display Mode")
        metricLabel.stringValue = language.text("单项主指标", "Single Metric")
        compactMetricsLabel.stringValue = language.text("紧凑显示项", "Compact Metrics")
        metricOrderLabel.stringValue = language.text("指标顺序", "Metric Order")
        separatorLabel.stringValue = language.text("分隔符", "Separator")
        precisionLabel.stringValue = language.text("数值精度", "Number Precision")
        intervalLabel.stringValue = language.text("CPU/内存刷新", "CPU/Memory Refresh")
        cpuThresholdLabel.stringValue = language.text("CPU 阈值", "CPU Threshold")
        memoryThresholdLabel.stringValue = language.text("内存阈值", "Memory Threshold")
        alertDurationLabel.stringValue = language.text("持续时间", "Sustain Duration")
        batteryLevelThresholdLabel.stringValue =
            language.text("低电量阈值", "Low Battery Threshold")
        batteryTemperatureThresholdLabel.stringValue =
            language.text("电池温度阈值", "Battery Temperature Threshold")
        diskFreeThresholdLabel.stringValue =
            language.text("磁盘可用阈值", "Disk Available Threshold")
        notificationStatusLabel.stringValue =
            language.text("通知权限", "Notification Permission")

        replaceItems(
            in: languagePopup,
            titles: AppLanguage.allCases.map {
                AppText.languageName($0, interfaceLanguage: language)
            }
        )
        replaceItems(
            in: displayModePopup,
            titles: StatusDisplayMode.allCases.map {
                AppText.displayModeName($0, language: language)
            }
        )
        replaceItems(
            in: metricPopup,
            titles: PrimaryMetric.allCases.map {
                AppText.metricName($0, language: language)
            }
        )
        replaceItems(
            in: metricOrderPopup,
            titles: currentSnapshot.metricOrder.map {
                AppText.metricName($0, language: language)
            }
        )
        replaceItems(
            in: separatorPopup,
            titles: [
                language.text("圆点（·）", "Dot (·)"),
                language.text("竖线（|）", "Bar (|)"),
                language.text("空格", "Space")
            ]
        )
        replaceItems(
            in: precisionPopup,
            titles: AppPreferences.allowedStatusDecimalPlaces.map {
                language.text("\($0) 位小数", "\($0) decimal places")
            }
        )
        replaceItems(
            in: intervalPopup,
            titles: AppPreferences.allowedRefreshIntervals.map {
                language.text("\(Int($0)) 秒", "\(Int($0)) sec")
            }
        )
        let thresholdTitles = AppPreferences.allowedAlertThresholds.map {
            "\(Int($0))%"
        }
        replaceItems(in: cpuThresholdPopup, titles: thresholdTitles)
        replaceItems(in: memoryThresholdPopup, titles: thresholdTitles)
        replaceItems(
            in: batteryLevelThresholdPopup,
            titles: AppPreferences.allowedBatteryLevelThresholds.map {
                "\(Int($0))%"
            }
        )
        replaceItems(
            in: batteryTemperatureThresholdPopup,
            titles: AppPreferences.allowedBatteryTemperatureThresholds.map {
                "\(Int($0))°C"
            }
        )
        replaceItems(
            in: diskFreeThresholdPopup,
            titles: AppPreferences.allowedDiskFreeThresholds.map {
                "\(Int($0))%"
            }
        )
        replaceItems(
            in: alertDurationPopup,
            titles: AppPreferences.allowedAlertDurations.map {
                language.text("\(Int($0)) 秒", "\(Int($0)) sec")
            }
        )

        compactMemoryCheckbox.title = language.text("内存", "Memory")
        compactBatteryCheckbox.title = language.text("电池", "Battery")
        compactNetworkCheckbox.title = language.text("网络", "Network")
        compactDiskCheckbox.title = language.text("磁盘", "Disk")
        moveMetricUpButton.title = language.text("上移", "Up")
        moveMetricDownButton.title = language.text("下移", "Down")
        loginCheckbox.title = language.text("登录时启动", "Launch at Login")
        sparklineCheckbox.title = language.text(
            "显示 CPU 和内存微型折线",
            "Show CPU and memory sparklines"
        )
        alertsCheckbox.title = language.text(
            "启用本地状态提醒（默认关闭）",
            "Enable local status alerts (off by default)"
        )
        cpuAlertCheckbox.title = language.text("CPU 持续高占用", "Sustained High CPU")
        memoryAlertCheckbox.title =
            language.text("内存持续高占用", "Sustained High Memory")
        thermalAlertCheckbox.title =
            language.text("严重系统热状态", "Serious Thermal State")
        batteryLevelAlertCheckbox.title =
            language.text("电池电量过低", "Low Battery Level")
        batteryTemperatureAlertCheckbox.title =
            language.text("电池温度过高", "High Battery Temperature")
        diskFreeAlertCheckbox.title =
            language.text("启动磁盘空间不足", "Low Startup Disk Space")
        testNotificationButton.title =
            language.text("发送测试提醒", "Send Test Alert")
        notificationSettingsButton.title =
            language.text("系统通知设置…", "Notification Settings…")
        resetButton.title = language.text("恢复默认设置…", "Restore Defaults…")
        sourceInfo.stringValue = Self.sourceInformation(language: language)

        languagePopup.setAccessibilityLabel(languageLabel.stringValue)
        displayModePopup.setAccessibilityLabel(displayModeLabel.stringValue)
        metricPopup.setAccessibilityLabel(metricLabel.stringValue)
        intervalPopup.setAccessibilityLabel(intervalLabel.stringValue)
        alertsCheckbox.setAccessibilityHelp(
            language.text(
                "总开关；各提醒类型可单独启用，默认不发送本地通知",
                "Master switch; each alert type is configurable and notifications are off by default"
            )
        )
        resetButton.setAccessibilityHelp(
            language.text(
                "恢复默认显示、采样、提醒和启动设置",
                "Restore default display, sampling, alert, and launch settings"
            )
        )
        applyNotificationStatus()
    }

    private func replaceItems(in popup: NSPopUpButton, titles: [String]) {
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
    }

    private func refresh() {
        let snapshot = currentSnapshot
        languagePopup.selectItem(
            at: AppLanguage.allCases.firstIndex(of: snapshot.language) ?? 0
        )
        displayModePopup.selectItem(
            at: StatusDisplayMode.allCases.firstIndex(of: snapshot.statusDisplayMode) ?? 0
        )
        metricPopup.selectItem(
            at: PrimaryMetric.allCases.firstIndex(of: snapshot.primaryMetric) ?? 0
        )
        if metricOrderPopup.indexOfSelectedItem < 0 {
            metricOrderPopup.selectItem(at: 0)
        }
        separatorPopup.selectItem(
            at: StatusSeparator.allCases.firstIndex(of: snapshot.statusSeparator) ?? 0
        )
        precisionPopup.selectItem(
            at: AppPreferences.allowedStatusDecimalPlaces.firstIndex(
                of: snapshot.statusDecimalPlaces
            ) ?? 0
        )
        intervalPopup.selectItem(
            at: AppPreferences.allowedRefreshIntervals.firstIndex(
                of: snapshot.refreshInterval
            ) ?? 0
        )
        loginCheckbox.state = loginItemController.isEnabled ? .on : .off
        sparklineCheckbox.state = snapshot.showsSparkline ? .on : .off
        alertsCheckbox.state = snapshot.alertsEnabled ? .on : .off
        compactCPUCheckbox.state = snapshot.compactMetrics.contains(.cpu) ? .on : .off
        compactMemoryCheckbox.state = snapshot.compactMetrics.contains(.memory) ? .on : .off
        compactBatteryCheckbox.state = snapshot.compactMetrics.contains(.battery) ? .on : .off
        compactNetworkCheckbox.state = snapshot.compactMetrics.contains(.network) ? .on : .off
        compactDiskCheckbox.state = snapshot.compactMetrics.contains(.disk) ? .on : .off
        cpuAlertCheckbox.state = snapshot.cpuAlertEnabled ? .on : .off
        memoryAlertCheckbox.state = snapshot.memoryAlertEnabled ? .on : .off
        thermalAlertCheckbox.state = snapshot.thermalAlertEnabled ? .on : .off
        batteryLevelAlertCheckbox.state =
            snapshot.batteryLevelAlertEnabled ? .on : .off
        batteryTemperatureAlertCheckbox.state =
            snapshot.batteryTemperatureAlertEnabled ? .on : .off
        diskFreeAlertCheckbox.state = snapshot.diskFreeAlertEnabled ? .on : .off
        cpuThresholdPopup.selectItem(
            at: AppPreferences.allowedAlertThresholds.firstIndex(
                of: snapshot.cpuAlertThreshold
            ) ?? 1
        )
        memoryThresholdPopup.selectItem(
            at: AppPreferences.allowedAlertThresholds.firstIndex(
                of: snapshot.memoryAlertThreshold
            ) ?? 1
        )
        batteryLevelThresholdPopup.selectItem(
            at: AppPreferences.allowedBatteryLevelThresholds.firstIndex(
                of: snapshot.batteryLevelAlertThreshold
            ) ?? 1
        )
        batteryTemperatureThresholdPopup.selectItem(
            at: AppPreferences.allowedBatteryTemperatureThresholds.firstIndex(
                of: snapshot.batteryTemperatureAlertThreshold
            ) ?? 1
        )
        diskFreeThresholdPopup.selectItem(
            at: AppPreferences.allowedDiskFreeThresholds.firstIndex(
                of: snapshot.diskFreeAlertThreshold
            ) ?? 1
        )
        alertDurationPopup.selectItem(
            at: AppPreferences.allowedAlertDurations.firstIndex(
                of: snapshot.alertSustainDuration
            ) ?? 0
        )

        let compactEnabled = snapshot.statusDisplayMode == .compact
        compactCPUCheckbox.isEnabled = compactEnabled
        compactMemoryCheckbox.isEnabled = compactEnabled
        compactBatteryCheckbox.isEnabled = compactEnabled
        compactNetworkCheckbox.isEnabled = compactEnabled
        compactDiskCheckbox.isEnabled = compactEnabled
        metricPopup.isEnabled = !compactEnabled
        let alertControls: [NSControl] = [
            cpuAlertCheckbox,
            memoryAlertCheckbox,
            thermalAlertCheckbox,
            batteryLevelAlertCheckbox,
            batteryTemperatureAlertCheckbox,
            diskFreeAlertCheckbox
        ]
        alertControls.forEach { $0.isEnabled = snapshot.alertsEnabled }
        cpuThresholdPopup.isEnabled =
            snapshot.alertsEnabled && snapshot.cpuAlertEnabled
        memoryThresholdPopup.isEnabled =
            snapshot.alertsEnabled && snapshot.memoryAlertEnabled
        batteryLevelThresholdPopup.isEnabled =
            snapshot.alertsEnabled && snapshot.batteryLevelAlertEnabled
        batteryTemperatureThresholdPopup.isEnabled =
            snapshot.alertsEnabled && snapshot.batteryTemperatureAlertEnabled
        diskFreeThresholdPopup.isEnabled =
            snapshot.alertsEnabled && snapshot.diskFreeAlertEnabled
        alertDurationPopup.isEnabled = snapshot.alertsEnabled
        applyNotificationStatus()
        updateMetricMoveButtons()
    }

    private func settingRow(
        _ label: NSTextField,
        control: NSView
    ) -> NSStackView {
        let row = NSStackView(views: [label, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 492).isActive = true
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 492).isActive = true
        return box
    }

    @objc private func languageChanged() {
        let index = max(0, languagePopup.indexOfSelectedItem)
        preferences.setLanguage(AppLanguage.allCases[index])
    }

    @objc private func displayModeChanged() {
        let index = max(0, displayModePopup.indexOfSelectedItem)
        preferences.setStatusDisplayMode(StatusDisplayMode.allCases[index])
    }

    @objc private func metricChanged() {
        let index = max(0, metricPopup.indexOfSelectedItem)
        preferences.setPrimaryMetric(PrimaryMetric.allCases[index])
    }

    @objc private func compactMetricsChanged() {
        let selected: [PrimaryMetric] = [
            compactCPUCheckbox.state == .on ? .cpu : nil,
            compactMemoryCheckbox.state == .on ? .memory : nil,
            compactBatteryCheckbox.state == .on ? .battery : nil,
            compactNetworkCheckbox.state == .on ? .network : nil,
            compactDiskCheckbox.state == .on ? .disk : nil
        ].compactMap { $0 }
        guard !selected.isEmpty else {
            NSSound.beep()
            refresh()
            return
        }
        preferences.setCompactMetrics(selected)
    }

    @objc private func metricOrderSelectionChanged() {
        updateMetricMoveButtons()
    }

    @objc private func moveMetricUp() {
        moveSelectedMetric(by: -1)
    }

    @objc private func moveMetricDown() {
        moveSelectedMetric(by: 1)
    }

    private func moveSelectedMetric(by offset: Int) {
        let index = metricOrderPopup.indexOfSelectedItem
        let destination = index + offset
        guard index >= 0,
              destination >= 0,
              destination < currentSnapshot.metricOrder.count else {
            NSSound.beep()
            return
        }
        var order = currentSnapshot.metricOrder
        order.swapAt(index, destination)
        preferences.setMetricOrder(order)
        metricOrderPopup.selectItem(at: destination)
        updateMetricMoveButtons()
    }

    @objc private func separatorChanged() {
        let index = max(0, separatorPopup.indexOfSelectedItem)
        preferences.setStatusSeparator(StatusSeparator.allCases[index])
    }

    @objc private func precisionChanged() {
        let index = max(0, precisionPopup.indexOfSelectedItem)
        preferences.setStatusDecimalPlaces(
            AppPreferences.allowedStatusDecimalPlaces[index]
        )
    }

    @objc private func intervalChanged() {
        let index = max(0, intervalPopup.indexOfSelectedItem)
        preferences.setRefreshInterval(
            AppPreferences.allowedRefreshIntervals[index]
        )
    }

    @objc private func loginChanged() {
        let enabled = loginCheckbox.state == .on
        switch loginItemController.setEnabled(enabled) {
        case .enabled:
            preferences.setLaunchAtLogin(true)
        case .disabled:
            preferences.setLaunchAtLogin(false)
        case .requiresApproval:
            preferences.setLaunchAtLogin(true)
            presentMessage(
                title: currentSnapshot.language.text(
                    "需要用户批准",
                    "User Approval Required"
                ),
                message: currentSnapshot.language.text(
                    "请在“系统设置 → 通用 → 登录项”中允许 Metrilens。",
                    "Allow Metrilens in System Settings → General → Login Items."
                )
            )
        case let .failed(error):
            loginCheckbox.state = enabled ? .off : .on
            presentMessage(
                title: currentSnapshot.language.text(
                    "无法更新登录项",
                    "Could Not Update Login Item"
                ),
                message: error.localizedDescription
            )
        }
    }

    @objc private func sparklineChanged() {
        preferences.setShowsSparkline(sparklineCheckbox.state == .on)
    }

    @objc private func alertsChanged() {
        preferences.setAlertsEnabled(alertsCheckbox.state == .on)
    }

    @objc private func alertKindChanged(_ sender: NSButton) {
        guard let kind = Self.alertKind(tag: sender.tag) else { return }
        preferences.setAlertEnabled(sender.state == .on, kind: kind)
    }

    @objc private func cpuThresholdChanged() {
        let index = max(0, cpuThresholdPopup.indexOfSelectedItem)
        preferences.setCPUAlertThreshold(
            AppPreferences.allowedAlertThresholds[index]
        )
    }

    @objc private func memoryThresholdChanged() {
        let index = max(0, memoryThresholdPopup.indexOfSelectedItem)
        preferences.setMemoryAlertThreshold(
            AppPreferences.allowedAlertThresholds[index]
        )
    }

    @objc private func batteryLevelThresholdChanged() {
        let index = max(0, batteryLevelThresholdPopup.indexOfSelectedItem)
        preferences.setBatteryLevelAlertThreshold(
            AppPreferences.allowedBatteryLevelThresholds[index]
        )
    }

    @objc private func batteryTemperatureThresholdChanged() {
        let index = max(0, batteryTemperatureThresholdPopup.indexOfSelectedItem)
        preferences.setBatteryTemperatureAlertThreshold(
            AppPreferences.allowedBatteryTemperatureThresholds[index]
        )
    }

    @objc private func diskFreeThresholdChanged() {
        let index = max(0, diskFreeThresholdPopup.indexOfSelectedItem)
        preferences.setDiskFreeAlertThreshold(
            AppPreferences.allowedDiskFreeThresholds[index]
        )
    }

    @objc private func alertDurationChanged() {
        let index = max(0, alertDurationPopup.indexOfSelectedItem)
        preferences.setAlertSustainDuration(
            AppPreferences.allowedAlertDurations[index]
        )
    }

    @objc private func testNotification() {
        onTestNotification?()
    }

    @objc private func openNotificationSettings() {
        onOpenNotificationSettings?()
    }

    @objc private func confirmReset() {
        let language = currentSnapshot.language
        let alert = NSAlert()
        alert.messageText = language.text(
            "恢复默认设置？",
            "Restore Default Settings?"
        )
        alert.informativeText = language.text(
            "菜单栏、刷新频率、提醒、登录项和图表设置将恢复默认值。",
            "Menu bar, refresh, alert, login, and chart settings will be restored."
        )
        alert.addButton(withTitle: language.text("恢复默认设置", "Restore Defaults"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.resetToDefaults()
        }
    }

    private func resetToDefaults() {
        switch loginItemController.setEnabled(false) {
        case .disabled:
            preferences.resetToDefaults()
            setPreferences(preferences.snapshot)
        case let .failed(error):
            presentMessage(
                title: currentSnapshot.language.text(
                    "无法关闭登录项",
                    "Could Not Disable Login Item"
                ),
                message: error.localizedDescription
            )
        case .enabled, .requiresApproval:
            presentMessage(
                title: currentSnapshot.language.text(
                    "无法关闭登录项",
                    "Could Not Disable Login Item"
                ),
                message: currentSnapshot.language.text(
                    "请先在“系统设置 → 通用 → 登录项”中关闭 Metrilens。",
                    "Disable Metrilens in System Settings → General → Login Items first."
                )
            )
        }
    }

    private func presentMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let window {
            alert.beginSheetModal(for: window)
        }
    }

    private func applyNotificationStatus() {
        let language = currentSnapshot.language
        switch notificationAuthorizationState {
        case .notDetermined:
            notificationStatusValue.stringValue =
                language.text("尚未请求", "Not Requested")
        case .denied:
            notificationStatusValue.stringValue =
                language.text("已拒绝", "Denied")
        case .authorized:
            notificationStatusValue.stringValue =
                language.text("已允许", "Allowed")
        case .provisional:
            notificationStatusValue.stringValue =
                language.text("临时允许", "Provisional")
        case .unknown:
            notificationStatusValue.stringValue =
                language.text("读取中", "Checking")
        }
        notificationStatusValue.textColor =
            notificationAuthorizationState == .denied
                ? .systemRed
                : .secondaryLabelColor
        testNotificationButton.isEnabled =
            notificationAuthorizationState != .denied
        notificationSettingsButton.isHidden = false
    }

    private func updateMetricMoveButtons() {
        let index = metricOrderPopup.indexOfSelectedItem
        moveMetricUpButton.isEnabled = index > 0
        moveMetricDownButton.isEnabled =
            index >= 0 && index < currentSnapshot.metricOrder.count - 1
    }

    private static func alertTag(_ kind: MetricAlertKind) -> Int {
        switch kind {
        case .cpu: return 1
        case .memory: return 2
        case .thermal: return 3
        case .batteryLevel: return 4
        case .batteryTemperature: return 5
        case .diskFree: return 6
        }
    }

    private static func alertKind(tag: Int) -> MetricAlertKind? {
        switch tag {
        case 1: return .cpu
        case 2: return .memory
        case 3: return .thermal
        case 4: return .batteryLevel
        case 5: return .batteryTemperature
        case 6: return .diskFree
        default: return nil
        }
    }

    private static func sourceInformation(language: AppLanguage) -> String {
        language.text(
            sourceInformation,
            "Temperature: Metrilens reads AppleSmartBattery battery temperature only. "
                + "It separates the resettable session maximum from the device lifetime maximum. "
                + "Precise CPU/GPU temperature is outside the current scope.\n\n"
                + "Memory: “Metrilens Memory” is internal + wired + compressor memory. "
                + "This stable product definition may differ from Activity Monitor."
        )
    }
}

private final class PreferencesDocumentView: NSView {
    override var isFlipped: Bool { true }
}
