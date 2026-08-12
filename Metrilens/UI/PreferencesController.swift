import AppKit

final class PreferencesController: NSWindowController {
    private let preferences: AppPreferences
    private let loginItemController: LoginItemController
    private let form = PreferencesForm()
    private var currentSnapshot: PreferencesSnapshot
    private var notificationAuthorizationState: NotificationAuthorizationState = .unknown

    var onTestNotification: (() -> Void)?
    var onOpenNotificationSettings: (() -> Void)?
    var onRefreshNotificationStatus: (() -> Void)?

    init(preferences: AppPreferences, loginItemController: LoginItemController) {
        self.preferences = preferences
        self.loginItemController = loginItemController
        currentSnapshot = preferences.snapshot
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        super.init(window: window)
        configureForm()
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
        form.updateNotificationStatus(
            state,
            language: currentSnapshot.display.language
        )
    }

    func setPreferences(_ snapshot: PreferencesSnapshot) {
        currentSnapshot = snapshot
        window?.title = snapshot.display.language.localized("Metrilens Settings")
        render()
    }

    func initialScrollStateForTesting() -> (
        documentIsFlipped: Bool,
        visibleMinY: CGFloat,
        languageControlVisible: Bool
    ) {
        window?.contentView?.layoutSubtreeIfNeeded()
        return form.initialScrollState()
    }

    private func configureForm() {
        guard let contentView = window?.contentView else { return }
        contentView.addSubview(form)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            form.topAnchor.constraint(equalTo: contentView.topAnchor),
            form.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        form.connect(
            target: self,
            actions: PreferencesFormActions(
                languageChanged: #selector(languageChanged),
                displayModeChanged: #selector(displayModeChanged),
                metricChanged: #selector(metricChanged),
                compactMetricsChanged: #selector(compactMetricsChanged),
                metricOrderSelectionChanged: #selector(metricOrderSelectionChanged),
                separatorChanged: #selector(separatorChanged),
                precisionChanged: #selector(precisionChanged),
                intervalChanged: #selector(intervalChanged),
                loginChanged: #selector(loginChanged),
                sparklineChanged: #selector(sparklineChanged),
                alertsChanged: #selector(alertsChanged),
                alertKindChanged: #selector(alertKindChanged(_:)),
                cpuThresholdChanged: #selector(cpuThresholdChanged),
                memoryThresholdChanged: #selector(memoryThresholdChanged),
                batteryLevelThresholdChanged: #selector(batteryLevelThresholdChanged),
                batteryTemperatureThresholdChanged:
                    #selector(batteryTemperatureThresholdChanged),
                diskFreeThresholdChanged: #selector(diskFreeThresholdChanged),
                alertDurationChanged: #selector(alertDurationChanged),
                moveMetricUp: #selector(moveMetricUp),
                moveMetricDown: #selector(moveMetricDown),
                testNotification: #selector(testNotification),
                openNotificationSettings: #selector(openNotificationSettings),
                confirmReset: #selector(confirmReset)
            )
        )
        window?.initialFirstResponder = form.languagePopup
        window?.setAccessibilityIdentifier("metrilens.preferences.window")
    }

    private func render() {
        form.render(
            snapshot: currentSnapshot,
            loginItemEnabled: loginItemController.isEnabled,
            notificationState: notificationAuthorizationState
        )
    }

    @objc private func languageChanged() {
        let index = max(0, form.languagePopup.indexOfSelectedItem)
        preferences.updateDisplay { $0.language = AppLanguage.allCases[index] }
    }

    @objc private func displayModeChanged() {
        let index = max(0, form.displayModePopup.indexOfSelectedItem)
        preferences.updateDisplay {
            $0.statusDisplayMode = StatusDisplayMode.allCases[index]
        }
    }

    @objc private func metricChanged() {
        let index = max(0, form.metricPopup.indexOfSelectedItem)
        preferences.updateDisplay { $0.primaryMetric = PrimaryMetric.allCases[index] }
    }

    @objc private func compactMetricsChanged() {
        let selected: [PrimaryMetric] = [
            form.compactCPUCheckbox.state == .on ? .cpu : nil,
            form.compactMemoryCheckbox.state == .on ? .memory : nil,
            form.compactBatteryCheckbox.state == .on ? .battery : nil,
            form.compactNetworkCheckbox.state == .on ? .network : nil,
            form.compactDiskCheckbox.state == .on ? .disk : nil
        ].compactMap { $0 }
        guard !selected.isEmpty else {
            NSSound.beep()
            render()
            return
        }
        preferences.updateDisplay { $0.compactMetrics = selected }
    }

    @objc private func metricOrderSelectionChanged() {
        form.updateMetricMoveButtons(
            metricCount: currentSnapshot.display.metricOrder.count
        )
    }

    @objc private func moveMetricUp() {
        moveSelectedMetric(by: -1)
    }

    @objc private func moveMetricDown() {
        moveSelectedMetric(by: 1)
    }

    private func moveSelectedMetric(by offset: Int) {
        let index = form.metricOrderPopup.indexOfSelectedItem
        let destination = index + offset
        guard index >= 0,
              destination >= 0,
              destination < currentSnapshot.display.metricOrder.count else {
            NSSound.beep()
            return
        }
        var order = currentSnapshot.display.metricOrder
        order.swapAt(index, destination)
        preferences.updateDisplay { $0.metricOrder = order }
        form.metricOrderPopup.selectItem(at: destination)
        form.updateMetricMoveButtons(metricCount: order.count)
    }

    @objc private func separatorChanged() {
        let index = max(0, form.separatorPopup.indexOfSelectedItem)
        preferences.updateDisplay {
            $0.statusSeparator = StatusSeparator.allCases[index]
        }
    }

    @objc private func precisionChanged() {
        let index = max(0, form.precisionPopup.indexOfSelectedItem)
        preferences.updateDisplay {
            $0.statusDecimalPlaces = AppPreferences.allowedStatusDecimalPlaces[index]
        }
    }

    @objc private func intervalChanged() {
        let index = max(0, form.intervalPopup.indexOfSelectedItem)
        preferences.updateSampling {
            $0.refreshInterval = AppPreferences.allowedRefreshIntervals[index]
        }
    }

    @objc private func loginChanged() {
        let enabled = form.loginCheckbox.state == .on
        switch loginItemController.setEnabled(enabled) {
        case .enabled:
            preferences.updateSystem { $0.launchAtLogin = true }
        case .disabled:
            preferences.updateSystem { $0.launchAtLogin = false }
        case .requiresApproval:
            preferences.updateSystem { $0.launchAtLogin = true }
            presentMessage(
                title: currentSnapshot.display.language.localized(
                    "User Approval Required"
                ),
                message: currentSnapshot.display.language.localized(
                    "Allow Metrilens in System Settings → General → Login Items."
                )
            )
        case let .failed(error):
            form.loginCheckbox.state = enabled ? .off : .on
            presentMessage(
                title: currentSnapshot.display.language.localized(
                    "Could Not Update Login Item"
                ),
                message: error.localizedDescription
            )
        }
    }

    @objc private func sparklineChanged() {
        preferences.updateSampling {
            $0.showsSparkline = form.sparklineCheckbox.state == .on
        }
    }

    @objc private func alertsChanged() {
        preferences.updateAlerts { $0.enabled = form.alertsCheckbox.state == .on }
    }

    @objc private func alertKindChanged(_ sender: NSButton) {
        guard let kind = PreferencesForm.alertKind(tag: sender.tag) else { return }
        preferences.updateAlerts {
            if sender.state == .on {
                $0.enabledKinds.insert(kind)
            } else {
                $0.enabledKinds.remove(kind)
            }
        }
    }

    @objc private func cpuThresholdChanged() {
        let index = max(0, form.cpuThresholdPopup.indexOfSelectedItem)
        preferences.updateAlerts {
            $0.thresholds.cpu = AppPreferences.allowedAlertThresholds[index]
        }
    }

    @objc private func memoryThresholdChanged() {
        let index = max(0, form.memoryThresholdPopup.indexOfSelectedItem)
        preferences.updateAlerts {
            $0.thresholds.memory = AppPreferences.allowedAlertThresholds[index]
        }
    }

    @objc private func batteryLevelThresholdChanged() {
        let index = max(0, form.batteryLevelThresholdPopup.indexOfSelectedItem)
        preferences.updateAlerts {
            $0.thresholds.batteryLevel =
                AppPreferences.allowedBatteryLevelThresholds[index]
        }
    }

    @objc private func batteryTemperatureThresholdChanged() {
        let index = max(0, form.batteryTemperatureThresholdPopup.indexOfSelectedItem)
        preferences.updateAlerts {
            $0.thresholds.batteryTemperature =
                AppPreferences.allowedBatteryTemperatureThresholds[index]
        }
    }

    @objc private func diskFreeThresholdChanged() {
        let index = max(0, form.diskFreeThresholdPopup.indexOfSelectedItem)
        preferences.updateAlerts {
            $0.thresholds.diskFree = AppPreferences.allowedDiskFreeThresholds[index]
        }
    }

    @objc private func alertDurationChanged() {
        let index = max(0, form.alertDurationPopup.indexOfSelectedItem)
        preferences.updateAlerts {
            $0.sustainDuration = AppPreferences.allowedAlertDurations[index]
        }
    }

    @objc private func testNotification() {
        onTestNotification?()
    }

    @objc private func openNotificationSettings() {
        onOpenNotificationSettings?()
    }

    @objc private func confirmReset() {
        let language = currentSnapshot.display.language
        let alert = NSAlert()
        alert.messageText = language.localized("Restore Default Settings?")
        alert.informativeText = language.localized(
            "Menu bar, refresh, alert, login, and chart settings will be restored."
        )
        alert.addButton(withTitle: language.localized("Restore Defaults"))
        alert.addButton(withTitle: language.localized("Cancel"))
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
                title: currentSnapshot.display.language.localized(
                    "Could Not Disable Login Item"
                ),
                message: error.localizedDescription
            )
        case .enabled, .requiresApproval:
            presentMessage(
                title: currentSnapshot.display.language.localized(
                    "Could Not Disable Login Item"
                ),
                message: currentSnapshot.display.language.localized(
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
}
