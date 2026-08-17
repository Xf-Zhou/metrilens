import AppKit

struct PreferencesFormActions {
    let languageChanged: Selector
    let interfaceStyleChanged: Selector
    let displayModeChanged: Selector
    let metricChanged: Selector
    let compactMetricsChanged: Selector
    let metricOrderSelectionChanged: Selector
    let separatorChanged: Selector
    let precisionChanged: Selector
    let intervalChanged: Selector
    let loginChanged: Selector
    let sparklineChanged: Selector
    let alertsChanged: Selector
    let alertKindChanged: Selector
    let cpuThresholdChanged: Selector
    let memoryThresholdChanged: Selector
    let batteryLevelThresholdChanged: Selector
    let batteryTemperatureThresholdChanged: Selector
    let diskFreeThresholdChanged: Selector
    let alertDurationChanged: Selector
    let moveMetricUp: Selector
    let moveMetricDown: Selector
    let testNotification: Selector
    let openNotificationSettings: Selector
    let confirmReset: Selector
}

final class PreferencesForm: NSView {
    let pageSelector = NSSegmentedControl()
    let languagePopup = NSPopUpButton()
    let interfaceStylePopup = NSPopUpButton()
    let interfaceStylePreview = InterfaceStylePreviewView()
    let displayModePopup = NSPopUpButton()
    let metricPopup = NSPopUpButton()
    let metricOrderPopup = NSPopUpButton()
    let separatorPopup = NSPopUpButton()
    let precisionPopup = NSPopUpButton()
    let intervalPopup = NSPopUpButton()
    let cpuThresholdPopup = NSPopUpButton()
    let memoryThresholdPopup = NSPopUpButton()
    let alertDurationPopup = NSPopUpButton()
    let batteryLevelThresholdPopup = NSPopUpButton()
    let batteryTemperatureThresholdPopup = NSPopUpButton()
    let diskFreeThresholdPopup = NSPopUpButton()
    let loginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let sparklineCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let alertsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let compactCPUCheckbox = NSButton(checkboxWithTitle: "CPU", target: nil, action: nil)
    let compactMemoryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let compactBatteryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let compactNetworkCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let compactDiskCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let cpuAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let memoryAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let thermalAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let batteryLevelAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let batteryTemperatureAlertCheckbox = NSButton(
        checkboxWithTitle: "",
        target: nil,
        action: nil
    )
    let diskFreeAlertCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let moveMetricUpButton = NSButton()
    let moveMetricDownButton = NSButton()
    let testNotificationButton = NSButton()
    let notificationSettingsButton = NSButton()
    let notificationStatusValue = NSTextField(labelWithString: "—")
    let resetButton = NSButton()

    private let sourceInfo = NSTextField(wrappingLabelWithString: "")
    private let displaySectionTitle = NSTextField(labelWithString: "")
    private let samplingSectionTitle = NSTextField(labelWithString: "")
    private let alertsSectionTitle = NSTextField(labelWithString: "")
    private let systemSectionTitle = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let interfaceStyleLabel = NSTextField(labelWithString: "")
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
    private let generalPage = NSStackView()
    private let displayPage = NSStackView()
    private let alertsPage = NSStackView()
    private var cpuThresholdRow = NSStackView()
    private var memoryThresholdRow = NSStackView()
    private var batteryLevelThresholdRow = NSStackView()
    private var batteryTemperatureThresholdRow = NSStackView()
    private var diskFreeThresholdRow = NSStackView()
    private var alertDurationRow = NSStackView()
    private weak var contentScrollView: NSScrollView?
    private weak var contentDocumentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityIdentifier("metrilens.preferences.form")
        buildContent()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func connect(target: AnyObject, actions: PreferencesFormActions) {
        configurePopup(languagePopup, target: target, action: actions.languageChanged)
        configurePopup(
            interfaceStylePopup,
            target: target,
            action: actions.interfaceStyleChanged
        )
        configurePopup(displayModePopup, target: target, action: actions.displayModeChanged)
        configurePopup(metricPopup, target: target, action: actions.metricChanged)
        configurePopup(
            metricOrderPopup,
            target: target,
            action: actions.metricOrderSelectionChanged
        )
        configurePopup(separatorPopup, target: target, action: actions.separatorChanged)
        configurePopup(precisionPopup, target: target, action: actions.precisionChanged)
        configurePopup(intervalPopup, target: target, action: actions.intervalChanged)
        configurePopup(cpuThresholdPopup, target: target, action: actions.cpuThresholdChanged)
        configurePopup(
            memoryThresholdPopup,
            target: target,
            action: actions.memoryThresholdChanged
        )
        configurePopup(
            alertDurationPopup,
            target: target,
            action: actions.alertDurationChanged
        )
        configurePopup(
            batteryLevelThresholdPopup,
            target: target,
            action: actions.batteryLevelThresholdChanged
        )
        configurePopup(
            batteryTemperatureThresholdPopup,
            target: target,
            action: actions.batteryTemperatureThresholdChanged
        )
        configurePopup(
            diskFreeThresholdPopup,
            target: target,
            action: actions.diskFreeThresholdChanged
        )

        configureCheckbox(loginCheckbox, target: target, action: actions.loginChanged)
        configureCheckbox(sparklineCheckbox, target: target, action: actions.sparklineChanged)
        configureCheckbox(alertsCheckbox, target: target, action: actions.alertsChanged)
        for checkbox in compactMetricCheckboxes {
            configureCheckbox(
                checkbox,
                target: target,
                action: actions.compactMetricsChanged
            )
        }
        for (checkbox, kind) in alertCheckboxes {
            checkbox.tag = Self.alertTag(kind)
            configureCheckbox(checkbox, target: target, action: actions.alertKindChanged)
        }

        moveMetricUpButton.target = target
        moveMetricUpButton.action = actions.moveMetricUp
        moveMetricDownButton.target = target
        moveMetricDownButton.action = actions.moveMetricDown
        testNotificationButton.target = target
        testNotificationButton.action = actions.testNotification
        notificationSettingsButton.target = target
        notificationSettingsButton.action = actions.openNotificationSettings
        resetButton.target = target
        resetButton.action = actions.confirmReset
    }

    func render(
        snapshot: PreferencesSnapshot,
        loginItemEnabled: Bool,
        notificationState: NotificationAuthorizationState
    ) {
        applyLocalization(snapshot: snapshot)
        refresh(
            snapshot: snapshot,
            loginItemEnabled: loginItemEnabled,
            notificationState: notificationState
        )
    }

    func updateNotificationStatus(
        _ state: NotificationAuthorizationState,
        language: AppLanguage
    ) {
        applyNotificationStatus(state, language: language)
    }

    func initialScrollState() -> (
        documentIsFlipped: Bool,
        visibleMinY: CGFloat,
        languageControlVisible: Bool
    ) {
        layoutSubtreeIfNeeded()
        guard let document = contentDocumentView,
              let scrollView = contentScrollView else {
            return (false, -1, false)
        }
        let languageFrame = languagePopup.convert(languagePopup.bounds, to: document)
        return (
            document.isFlipped,
            scrollView.documentVisibleRect.minY,
            scrollView.documentVisibleRect.intersects(languageFrame)
        )
    }

    func selectPageForTesting(_ index: Int) {
        pageSelector.selectedSegment = index
        showSelectedPage()
    }

    func pageVisibilityForTesting() -> (
        general: Bool,
        display: Bool,
        alerts: Bool
    ) {
        (!generalPage.isHidden, !displayPage.isHidden, !alertsPage.isHidden)
    }

    func alertThresholdVisibilityForTesting() -> (
        cpu: Bool,
        memory: Bool,
        batteryLevel: Bool,
        batteryTemperature: Bool,
        disk: Bool
    ) {
        (
            !cpuThresholdRow.isHidden,
            !memoryThresholdRow.isHidden,
            !batteryLevelThresholdRow.isHidden,
            !batteryTemperatureThresholdRow.isHidden,
            !diskFreeThresholdRow.isHidden
        )
    }

    func updateMetricMoveButtons(metricCount: Int) {
        let index = metricOrderPopup.indexOfSelectedItem
        moveMetricUpButton.isEnabled = index > 0
        moveMetricDownButton.isEnabled = index >= 0 && index < metricCount - 1
    }

    static func alertKind(tag: Int) -> MetricAlertKind? {
        MetricAlertKind.allCases.first { alertTag($0) == tag }
    }

    private var compactMetricCheckboxes: [NSButton] {
        [
            compactCPUCheckbox,
            compactMemoryCheckbox,
            compactBatteryCheckbox,
            compactNetworkCheckbox,
            compactDiskCheckbox
        ]
    }

    private var alertCheckboxes: [(NSButton, MetricAlertKind)] {
        [
            (cpuAlertCheckbox, .cpu),
            (memoryAlertCheckbox, .memory),
            (thermalAlertCheckbox, .thermal),
            (batteryLevelAlertCheckbox, .batteryLevel),
            (batteryTemperatureAlertCheckbox, .batteryTemperature),
            (diskFreeAlertCheckbox, .diskFree)
        ]
    }

    private func buildContent() {
        sourceInfo.textColor = .secondaryLabelColor
        sourceInfo.font = .systemFont(ofSize: 11)

        let compactControls = NSStackView(views: compactMetricCheckboxes)
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

        cpuThresholdRow = settingRow(cpuThresholdLabel, control: cpuThresholdPopup)
        memoryThresholdRow = settingRow(
            memoryThresholdLabel,
            control: memoryThresholdPopup
        )
        batteryLevelThresholdRow = settingRow(
            batteryLevelThresholdLabel,
            control: batteryLevelThresholdPopup
        )
        batteryTemperatureThresholdRow = settingRow(
            batteryTemperatureThresholdLabel,
            control: batteryTemperatureThresholdPopup
        )
        diskFreeThresholdRow = settingRow(
            diskFreeThresholdLabel,
            control: diskFreeThresholdPopup
        )
        alertDurationRow = settingRow(
            alertDurationLabel,
            control: alertDurationPopup
        )

        configurePage(
            generalPage,
            views: [
                samplingSectionTitle,
                settingRow(languageLabel, control: languagePopup),
                settingRow(intervalLabel, control: intervalPopup),
                sparklineCheckbox,
                separator(),
                systemSectionTitle,
                loginCheckbox,
                sourceInfo,
                resetButton
            ]
        )
        configurePage(
            displayPage,
            views: [
                displaySectionTitle,
                settingRow(interfaceStyleLabel, control: interfaceStylePopup),
                interfaceStylePreview,
                settingRow(displayModeLabel, control: displayModePopup),
                settingRow(metricLabel, control: metricPopup),
                settingRow(compactMetricsLabel, control: compactControls),
                settingRow(metricOrderLabel, control: orderControls),
                settingRow(separatorLabel, control: separatorPopup),
                settingRow(precisionLabel, control: precisionPopup)
            ]
        )
        configurePage(
            alertsPage,
            views: [
                alertsSectionTitle,
                alertsCheckbox,
                cpuAlertCheckbox,
                cpuThresholdRow,
                memoryAlertCheckbox,
                memoryThresholdRow,
                thermalAlertCheckbox,
                batteryLevelAlertCheckbox,
                batteryLevelThresholdRow,
                batteryTemperatureAlertCheckbox,
                batteryTemperatureThresholdRow,
                diskFreeAlertCheckbox,
                diskFreeThresholdRow,
                alertDurationRow,
                separator(),
                settingRow(notificationStatusLabel, control: notificationStatusValue),
                notificationControls
            ]
        )

        pageSelector.segmentCount = 3
        pageSelector.trackingMode = .selectOne
        pageSelector.selectedSegment = 0
        pageSelector.target = self
        pageSelector.action = #selector(pageChanged)
        pageSelector.setAccessibilityIdentifier("metrilens.preferences.pages")
        pageSelector.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let stack = NSStackView(views: [
            pageSelector,
            separator(),
            generalPage,
            displayPage,
            alertsPage
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        for page in [generalPage, displayPage, alertsPage] {
            page.widthAnchor.constraint(equalToConstant: 492).isActive = true
        }
        showSelectedPage()

        let documentView = PreferencesDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView = scrollView
        contentDocumentView = documentView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(
                equalTo: documentView.leadingAnchor,
                constant: 24
            ),
            stack.trailingAnchor.constraint(
                equalTo: documentView.trailingAnchor,
                constant: -24
            ),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(
                equalTo: documentView.bottomAnchor,
                constant: -22
            ),
            sourceInfo.widthAnchor.constraint(equalToConstant: 492)
        ])
    }

    private func configurePage(_ page: NSStackView, views: [NSView]) {
        page.setViews(views, in: .top)
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 11
    }

    @objc private func pageChanged() {
        showSelectedPage()
        guard let scrollView = contentScrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func showSelectedPage() {
        let selected = max(0, pageSelector.selectedSegment)
        generalPage.isHidden = selected != 0
        displayPage.isHidden = selected != 1
        alertsPage.isHidden = selected != 2
    }

    private func applyLocalization(snapshot: PreferencesSnapshot) {
        let language = snapshot.display.language
        pageSelector.setLabel(language.localized("General"), forSegment: 0)
        pageSelector.setLabel(language.localized("Display"), forSegment: 1)
        pageSelector.setLabel(language.localized("Alerts"), forSegment: 2)
        displaySectionTitle.stringValue = language.localized("Menu Bar")
        samplingSectionTitle.stringValue = language.localized("Sampling & Charts")
        alertsSectionTitle.stringValue = language.localized("Local Alerts")
        systemSectionTitle.stringValue = language.localized("System & Notes")
        for title in [
            displaySectionTitle,
            samplingSectionTitle,
            alertsSectionTitle,
            systemSectionTitle
        ] {
            title.font = .systemFont(ofSize: 13, weight: .semibold)
        }

        languageLabel.stringValue = language.localized("Language")
        interfaceStyleLabel.stringValue = language.localized("Interface Style")
        displayModeLabel.stringValue = language.localized("Display Mode")
        metricLabel.stringValue = language.localized("Single Metric")
        compactMetricsLabel.stringValue = language.localized("Compact Metrics")
        metricOrderLabel.stringValue = language.localized("Metric Order")
        separatorLabel.stringValue = language.localized("Separator")
        precisionLabel.stringValue = language.localized("Number Precision")
        intervalLabel.stringValue = language.localized("Metric Refresh")
        cpuThresholdLabel.stringValue = language.localized("CPU Threshold")
        memoryThresholdLabel.stringValue = language.localized("Memory Threshold")
        alertDurationLabel.stringValue = language.localized("Sustain Duration")
        batteryLevelThresholdLabel.stringValue = language.localized("Low Battery Threshold")
        batteryTemperatureThresholdLabel.stringValue =
            language.localized("Battery Temperature Threshold")
        diskFreeThresholdLabel.stringValue = language.localized("Disk Available Threshold")
        notificationStatusLabel.stringValue = language.localized("Notification Permission")

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
            in: interfaceStylePopup,
            titles: InterfaceStyle.allCases.map {
                AppText.interfaceStyleName($0, language: language)
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
            titles: snapshot.display.metricOrder.map {
                AppText.metricName($0, language: language)
            }
        )
        replaceItems(
            in: separatorPopup,
            titles: [
                language.localized("Dot (·)"),
                language.localized("Bar (|)"),
                language.localized("Space")
            ]
        )
        replaceItems(
            in: precisionPopup,
            titles: AppPreferences.allowedStatusDecimalPlaces.map {
                language.localized("preferences.decimalPlaces", arguments: $0)
            }
        )
        replaceItems(
            in: intervalPopup,
            titles: AppPreferences.allowedRefreshIntervals.map {
                language.localized("preferences.seconds", arguments: Int($0))
            }
        )
        let thresholdTitles = AppPreferences.allowedAlertThresholds.map {
            "\(Int($0))%"
        }
        replaceItems(in: cpuThresholdPopup, titles: thresholdTitles)
        replaceItems(in: memoryThresholdPopup, titles: thresholdTitles)
        replaceItems(
            in: batteryLevelThresholdPopup,
            titles: AppPreferences.allowedBatteryLevelThresholds.map { "\(Int($0))%" }
        )
        replaceItems(
            in: batteryTemperatureThresholdPopup,
            titles: AppPreferences.allowedBatteryTemperatureThresholds.map {
                "\(Int($0))°C"
            }
        )
        replaceItems(
            in: diskFreeThresholdPopup,
            titles: AppPreferences.allowedDiskFreeThresholds.map { "\(Int($0))%" }
        )
        replaceItems(
            in: alertDurationPopup,
            titles: AppPreferences.allowedAlertDurations.map {
                language.localized("preferences.seconds", arguments: Int($0))
            }
        )

        compactMemoryCheckbox.title = language.localized("Memory")
        compactBatteryCheckbox.title = language.localized("Battery")
        compactNetworkCheckbox.title = language.localized("Network")
        compactDiskCheckbox.title = language.localized("Disk")
        moveMetricUpButton.title = ""
        moveMetricUpButton.image = NSImage(
            systemSymbolName: "arrow.up",
            accessibilityDescription: language.localized("Up")
        )
        moveMetricUpButton.toolTip = language.localized("Up")
        moveMetricUpButton.setAccessibilityLabel(language.localized("Up"))
        moveMetricDownButton.title = ""
        moveMetricDownButton.image = NSImage(
            systemSymbolName: "arrow.down",
            accessibilityDescription: language.localized("Down")
        )
        moveMetricDownButton.toolTip = language.localized("Down")
        moveMetricDownButton.setAccessibilityLabel(language.localized("Down"))
        loginCheckbox.title = language.localized("Launch at Login")
        sparklineCheckbox.title = language.localized("Show CPU and memory sparklines")
        alertsCheckbox.title = language.localized(
            "Enable local status alerts (off by default)"
        )
        cpuAlertCheckbox.title = language.localized("Sustained High CPU")
        memoryAlertCheckbox.title = language.localized("Sustained High Memory")
        thermalAlertCheckbox.title = language.localized("Serious Thermal State")
        batteryLevelAlertCheckbox.title = language.localized("Low Battery Level")
        batteryTemperatureAlertCheckbox.title =
            language.localized("settings.highBatteryTemperature")
        diskFreeAlertCheckbox.title = language.localized("Low Startup Disk Space")
        testNotificationButton.title = language.localized("Send Test Alert")
        notificationSettingsButton.title = language.localized("Notification Settings…")
        resetButton.title = language.localized("Restore Defaults…")
        sourceInfo.stringValue = language.localized("preferences.sourceInformation")

        languagePopup.setAccessibilityLabel(languageLabel.stringValue)
        interfaceStylePopup.setAccessibilityLabel(interfaceStyleLabel.stringValue)
        displayModePopup.setAccessibilityLabel(displayModeLabel.stringValue)
        metricPopup.setAccessibilityLabel(metricLabel.stringValue)
        intervalPopup.setAccessibilityLabel(intervalLabel.stringValue)
        alertsCheckbox.setAccessibilityHelp(
            language.localized(
                "Master switch; each alert type is configurable and notifications are off by default"
            )
        )
        resetButton.setAccessibilityHelp(
            language.localized(
                "Restore default display, sampling, alert, and launch settings"
            )
        )

        languagePopup.setAccessibilityIdentifier("metrilens.preferences.language")
        displayModePopup.setAccessibilityIdentifier("metrilens.preferences.displayMode")
        interfaceStylePopup.setAccessibilityIdentifier("metrilens.preferences.interfaceStyle")
        resetButton.setAccessibilityIdentifier("metrilens.preferences.reset")
    }

    private func refresh(
        snapshot: PreferencesSnapshot,
        loginItemEnabled: Bool,
        notificationState: NotificationAuthorizationState
    ) {
        languagePopup.selectItem(
            at: AppLanguage.allCases.firstIndex(of: snapshot.display.language) ?? 0
        )
        interfaceStylePopup.selectItem(
            at: InterfaceStyle.allCases.firstIndex(
                of: snapshot.display.interfaceStyle
            ) ?? 0
        )
        interfaceStylePreview.style = snapshot.display.interfaceStyle
        displayModePopup.selectItem(
            at: StatusDisplayMode.allCases.firstIndex(
                of: snapshot.display.statusDisplayMode
            ) ?? 0
        )
        metricPopup.selectItem(
            at: PrimaryMetric.allCases.firstIndex(of: snapshot.display.primaryMetric) ?? 0
        )
        if metricOrderPopup.indexOfSelectedItem < 0 {
            metricOrderPopup.selectItem(at: 0)
        }
        separatorPopup.selectItem(
            at: StatusSeparator.allCases.firstIndex(
                of: snapshot.display.statusSeparator
            ) ?? 0
        )
        precisionPopup.selectItem(
            at: AppPreferences.allowedStatusDecimalPlaces.firstIndex(
                of: snapshot.display.statusDecimalPlaces
            ) ?? 0
        )
        intervalPopup.selectItem(
            at: AppPreferences.allowedRefreshIntervals.firstIndex(
                of: snapshot.sampling.refreshInterval
            ) ?? 0
        )
        loginCheckbox.state = loginItemEnabled ? .on : .off
        sparklineCheckbox.state = snapshot.sampling.showsSparkline ? .on : .off
        alertsCheckbox.state = snapshot.alerts.enabled ? .on : .off
        compactCPUCheckbox.state = snapshot.display.compactMetrics.contains(.cpu) ? .on : .off
        compactMemoryCheckbox.state = snapshot.display.compactMetrics.contains(.memory) ? .on : .off
        compactBatteryCheckbox.state = snapshot.display.compactMetrics.contains(.battery) ? .on : .off
        compactNetworkCheckbox.state = snapshot.display.compactMetrics.contains(.network) ? .on : .off
        compactDiskCheckbox.state = snapshot.display.compactMetrics.contains(.disk) ? .on : .off
        cpuAlertCheckbox.state = snapshot.alerts.isEnabled(.cpu) ? .on : .off
        memoryAlertCheckbox.state = snapshot.alerts.isEnabled(.memory) ? .on : .off
        thermalAlertCheckbox.state = snapshot.alerts.isEnabled(.thermal) ? .on : .off
        batteryLevelAlertCheckbox.state = snapshot.alerts.isEnabled(.batteryLevel) ? .on : .off
        batteryTemperatureAlertCheckbox.state =
            snapshot.alerts.isEnabled(.batteryTemperature) ? .on : .off
        diskFreeAlertCheckbox.state = snapshot.alerts.isEnabled(.diskFree) ? .on : .off
        cpuThresholdPopup.selectItem(
            at: AppPreferences.allowedAlertThresholds.firstIndex(
                of: snapshot.alerts.thresholds.cpu
            ) ?? 1
        )
        memoryThresholdPopup.selectItem(
            at: AppPreferences.allowedAlertThresholds.firstIndex(
                of: snapshot.alerts.thresholds.memory
            ) ?? 1
        )
        batteryLevelThresholdPopup.selectItem(
            at: AppPreferences.allowedBatteryLevelThresholds.firstIndex(
                of: snapshot.alerts.thresholds.batteryLevel
            ) ?? 1
        )
        batteryTemperatureThresholdPopup.selectItem(
            at: AppPreferences.allowedBatteryTemperatureThresholds.firstIndex(
                of: snapshot.alerts.thresholds.batteryTemperature
            ) ?? 1
        )
        diskFreeThresholdPopup.selectItem(
            at: AppPreferences.allowedDiskFreeThresholds.firstIndex(
                of: snapshot.alerts.thresholds.diskFree
            ) ?? 1
        )
        alertDurationPopup.selectItem(
            at: AppPreferences.allowedAlertDurations.firstIndex(
                of: snapshot.alerts.sustainDuration
            ) ?? 0
        )

        let compactEnabled = snapshot.display.statusDisplayMode == .compact
        compactMetricCheckboxes.forEach { $0.isEnabled = compactEnabled }
        metricPopup.isEnabled = !compactEnabled
        alertCheckboxes.forEach { $0.0.isEnabled = snapshot.alerts.enabled }
        cpuThresholdPopup.isEnabled =
            snapshot.alerts.enabled && snapshot.alerts.isEnabled(.cpu)
        memoryThresholdPopup.isEnabled =
            snapshot.alerts.enabled && snapshot.alerts.isEnabled(.memory)
        batteryLevelThresholdPopup.isEnabled =
            snapshot.alerts.enabled && snapshot.alerts.isEnabled(.batteryLevel)
        batteryTemperatureThresholdPopup.isEnabled =
            snapshot.alerts.enabled && snapshot.alerts.isEnabled(.batteryTemperature)
        diskFreeThresholdPopup.isEnabled =
            snapshot.alerts.enabled && snapshot.alerts.isEnabled(.diskFree)
        alertDurationPopup.isEnabled = snapshot.alerts.enabled
        cpuThresholdRow.isHidden = !cpuThresholdPopup.isEnabled
        memoryThresholdRow.isHidden = !memoryThresholdPopup.isEnabled
        batteryLevelThresholdRow.isHidden = !batteryLevelThresholdPopup.isEnabled
        batteryTemperatureThresholdRow.isHidden =
            !batteryTemperatureThresholdPopup.isEnabled
        diskFreeThresholdRow.isHidden = !diskFreeThresholdPopup.isEnabled
        alertDurationRow.isHidden = !snapshot.alerts.enabled
        applyNotificationStatus(notificationState, language: snapshot.display.language)
        updateMetricMoveButtons(metricCount: snapshot.display.metricOrder.count)
    }

    private func applyNotificationStatus(
        _ state: NotificationAuthorizationState,
        language: AppLanguage
    ) {
        switch state {
        case .notDetermined:
            notificationStatusValue.stringValue = language.localized("Not Requested")
        case .denied:
            notificationStatusValue.stringValue = language.localized("Denied")
        case .authorized:
            notificationStatusValue.stringValue = language.localized("Allowed")
        case .provisional:
            notificationStatusValue.stringValue = language.localized("Provisional")
        case .unknown:
            notificationStatusValue.stringValue = language.localized("Checking")
        }
        notificationStatusValue.textColor = state == .denied ? .systemRed : .secondaryLabelColor
        testNotificationButton.isEnabled = state != .denied
        notificationSettingsButton.isHidden = false
    }

    private func configurePopup(
        _ popup: NSPopUpButton,
        target: AnyObject,
        action: Selector
    ) {
        popup.target = target
        popup.action = action
    }

    private func configureCheckbox(
        _ checkbox: NSButton,
        target: AnyObject,
        action: Selector
    ) {
        checkbox.target = target
        checkbox.action = action
    }

    private func replaceItems(in popup: NSPopUpButton, titles: [String]) {
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
    }

    private func settingRow(_ label: NSTextField, control: NSView) -> NSStackView {
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

    private static func alertTag(_ kind: MetricAlertKind) -> Int {
        MetricAlertKind.allCases.firstIndex(of: kind).map { $0 + 1 } ?? 0
    }
}

private final class PreferencesDocumentView: NSView {
    override var isFlipped: Bool { true }
}
