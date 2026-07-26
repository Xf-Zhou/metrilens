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
    private let intervalPopup = NSPopUpButton()
    private let cpuThresholdPopup = NSPopUpButton()
    private let memoryThresholdPopup = NSPopUpButton()
    private let alertDurationPopup = NSPopUpButton()
    private let loginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let sparklineCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let alertsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let compactCPUCheckbox = NSButton(checkboxWithTitle: "CPU", target: nil, action: nil)
    private let compactMemoryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let compactBatteryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
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
    private let intervalLabel = NSTextField(labelWithString: "")
    private let cpuThresholdLabel = NSTextField(labelWithString: "")
    private let memoryThresholdLabel = NSTextField(labelWithString: "")
    private let alertDurationLabel = NSTextField(labelWithString: "")

    private var currentSnapshot: PreferencesSnapshot

    init(preferences: AppPreferences, loginItemController: LoginItemController) {
        self.preferences = preferences
        self.loginItemController = loginItemController
        currentSnapshot = preferences.snapshot
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 660),
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
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setPreferences(_ snapshot: PreferencesSnapshot) {
        currentSnapshot = snapshot
        applyLocalization()
        refresh()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        configurePopup(languagePopup, action: #selector(languageChanged))
        configurePopup(displayModePopup, action: #selector(displayModeChanged))
        configurePopup(metricPopup, action: #selector(metricChanged))
        configurePopup(intervalPopup, action: #selector(intervalChanged))
        configurePopup(cpuThresholdPopup, action: #selector(cpuThresholdChanged))
        configurePopup(memoryThresholdPopup, action: #selector(memoryThresholdChanged))
        configurePopup(alertDurationPopup, action: #selector(alertDurationChanged))

        configureCheckbox(loginCheckbox, action: #selector(loginChanged))
        configureCheckbox(sparklineCheckbox, action: #selector(sparklineChanged))
        configureCheckbox(alertsCheckbox, action: #selector(alertsChanged))
        for checkbox in [
            compactCPUCheckbox,
            compactMemoryCheckbox,
            compactBatteryCheckbox
        ] {
            configureCheckbox(checkbox, action: #selector(compactMetricsChanged))
        }

        resetButton.target = self
        resetButton.action = #selector(confirmReset)
        sourceInfo.textColor = .secondaryLabelColor

        let compactControls = NSStackView(
            views: [
                compactCPUCheckbox,
                compactMemoryCheckbox,
                compactBatteryCheckbox
            ]
        )
        compactControls.orientation = .horizontal
        compactControls.spacing = 12

        let stack = NSStackView(views: [
            displaySectionTitle,
            settingRow(languageLabel, control: languagePopup),
            settingRow(displayModeLabel, control: displayModePopup),
            settingRow(metricLabel, control: metricPopup),
            settingRow(compactMetricsLabel, control: compactControls),
            separator(),
            samplingSectionTitle,
            settingRow(intervalLabel, control: intervalPopup),
            sparklineCheckbox,
            separator(),
            alertsSectionTitle,
            alertsCheckbox,
            settingRow(cpuThresholdLabel, control: cpuThresholdPopup),
            settingRow(memoryThresholdLabel, control: memoryThresholdPopup),
            settingRow(alertDurationLabel, control: alertDurationPopup),
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
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            sourceInfo.widthAnchor.constraint(equalToConstant: 452)
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
        intervalLabel.stringValue = language.text("CPU/内存刷新", "CPU/Memory Refresh")
        cpuThresholdLabel.stringValue = language.text("CPU 阈值", "CPU Threshold")
        memoryThresholdLabel.stringValue = language.text("内存阈值", "Memory Threshold")
        alertDurationLabel.stringValue = language.text("持续时间", "Sustain Duration")

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
            in: alertDurationPopup,
            titles: AppPreferences.allowedAlertDurations.map {
                language.text("\(Int($0)) 秒", "\(Int($0)) sec")
            }
        )

        compactMemoryCheckbox.title = language.text("内存", "Memory")
        compactBatteryCheckbox.title = language.text("电池", "Battery")
        loginCheckbox.title = language.text("登录时启动", "Launch at Login")
        sparklineCheckbox.title = language.text(
            "显示 CPU 和内存微型折线",
            "Show CPU and memory sparklines"
        )
        alertsCheckbox.title = language.text(
            "启用本地状态提醒（默认关闭）",
            "Enable local status alerts (off by default)"
        )
        resetButton.title = language.text("恢复默认设置…", "Restore Defaults…")
        sourceInfo.stringValue = Self.sourceInformation(language: language)

        languagePopup.setAccessibilityLabel(languageLabel.stringValue)
        displayModePopup.setAccessibilityLabel(displayModeLabel.stringValue)
        metricPopup.setAccessibilityLabel(metricLabel.stringValue)
        intervalPopup.setAccessibilityLabel(intervalLabel.stringValue)
        alertsCheckbox.setAccessibilityHelp(
            language.text(
                "仅在持续高占用或严重热状态时发送本地通知",
                "Only notify for sustained high usage or a serious thermal state"
            )
        )
        resetButton.setAccessibilityHelp(
            language.text(
                "恢复默认显示、采样、提醒和启动设置",
                "Restore default display, sampling, alert, and launch settings"
            )
        )
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
        alertDurationPopup.selectItem(
            at: AppPreferences.allowedAlertDurations.firstIndex(
                of: snapshot.alertSustainDuration
            ) ?? 0
        )

        let compactEnabled = snapshot.statusDisplayMode == .compact
        compactCPUCheckbox.isEnabled = compactEnabled
        compactMemoryCheckbox.isEnabled = compactEnabled
        compactBatteryCheckbox.isEnabled = compactEnabled
        metricPopup.isEnabled = !compactEnabled
        cpuThresholdPopup.isEnabled = snapshot.alertsEnabled
        memoryThresholdPopup.isEnabled = snapshot.alertsEnabled
        alertDurationPopup.isEnabled = snapshot.alertsEnabled
    }

    private func settingRow(
        _ label: NSTextField,
        control: NSView
    ) -> NSStackView {
        let row = NSStackView(views: [label, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 452).isActive = true
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 452).isActive = true
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
            compactBatteryCheckbox.state == .on ? .battery : nil
        ].compactMap { $0 }
        guard !selected.isEmpty else {
            NSSound.beep()
            refresh()
            return
        }
        preferences.setCompactMetrics(selected)
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

    @objc private func alertDurationChanged() {
        let index = max(0, alertDurationPopup.indexOfSelectedItem)
        preferences.setAlertSustainDuration(
            AppPreferences.allowedAlertDurations[index]
        )
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
