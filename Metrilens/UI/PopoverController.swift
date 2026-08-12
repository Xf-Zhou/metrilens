import AppKit

final class PopoverController: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    let cpuValue = NSTextField(labelWithString: "—")
    let cpuSummaryValue = NSTextField(labelWithString: "—")
    let memoryValue = NSTextField(labelWithString: "—")
    let memorySummaryValue = NSTextField(labelWithString: "—")
    let batteryValue = NSTextField(labelWithString: "—")
    let batteryLevelValue = NSTextField(labelWithString: "—")
    let batteryStateValue = NSTextField(labelWithString: "—")
    let batteryCyclesValue = NSTextField(labelWithString: "—")
    let batteryHealthValue = NSTextField(labelWithString: "—")
    let batterySessionMaximumValue = NSTextField(labelWithString: "—")
    let batteryMaximumValue = NSTextField(labelWithString: "—")
    let networkDownloadValue = NSTextField(labelWithString: "—")
    let networkUploadValue = NSTextField(labelWithString: "—")
    let diskUsageValue = NSTextField(labelWithString: "—")
    let diskFreeValue = NSTextField(labelWithString: "—")
    let thermalValue = NSTextField(labelWithString: "—")
    let heatDiagnosisValue = NSTextField(wrappingLabelWithString: "—")
    let updatedValue = NSTextField(labelWithString: "—")
    let contentScrollView = NSScrollView()
    let cpuSparkline = SparklineView()
    let memorySparkline = SparklineView()

    let titleLabel = NSTextField(labelWithString: "Metrilens")
    let cpuTitle = NSTextField(labelWithString: "CPU")
    let memoryTitle = NSTextField(labelWithString: "")
    let batterySectionTitle = NSTextField(labelWithString: "")
    let networkSectionTitle = NSTextField(labelWithString: "")
    let diskSectionTitle = NSTextField(labelWithString: "")
    let batteryTitle = NSTextField(labelWithString: "")
    let batteryLevelTitle = NSTextField(labelWithString: "")
    let batteryStateTitle = NSTextField(labelWithString: "")
    let batteryCyclesTitle = NSTextField(labelWithString: "")
    let batteryHealthTitle = NSTextField(labelWithString: "")
    let batterySessionMaximumTitle = NSTextField(labelWithString: "")
    let batteryMaximumTitle = NSTextField(labelWithString: "")
    let networkDownloadTitle = NSTextField(labelWithString: "")
    let networkUploadTitle = NSTextField(labelWithString: "")
    let diskUsageTitle = NSTextField(labelWithString: "")
    let diskFreeTitle = NSTextField(labelWithString: "")
    let thermalTitle = NSTextField(labelWithString: "")
    let heatDiagnosisTitle = NSTextField(labelWithString: "")
    let aboutButton = NSButton()
    let settingsButton = NSButton()
    let resetSessionMaximumButton = NSButton()
    let quitButton = NSButton()

    let batteryRow = NSStackView()
    let batteryHealthRow = NSStackView()
    let batterySessionMaximumRow = NSStackView()
    let batteryMaximumRow = NSStackView()
    let cpuSection = NSStackView()
    let memorySection = NSStackView()
    let batterySection = NSStackView()
    let networkSection = NSStackView()
    let diskSection = NSStackView()
    let metricSectionsStack = NSStackView()
    weak var contentStack: NSStackView?
    private var preferences: PreferencesSnapshot
    let keyboardFocusHandler: (NSWindow?) -> Void

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
        popover.contentViewController = PopoverLayoutBuilder.makeContentController(
            for: self,
            target: self,
            actions: PopoverLayoutActions(
                openAbout: #selector(openAbout),
                openPreferences: #selector(openPreferences),
                resetSessionMaximum: #selector(resetSessionMaximum),
                quitApplication: #selector(quitApplication)
            )
        )
        applyLocalization()
        applyDisplayPreferences()
        updateContentSize()
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            layoutContentView()
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

    func batteryHealthRowHiddenForTesting() -> Bool {
        batteryHealthRow.isHidden
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
        let language = preferences.display.language
        cpuValue.stringValue = PopoverMetricFormatter.cpuText(snapshot.cpu, language: language)
        setFailureReason(PopoverMetricFormatter.failureReason(
            snapshot.cpu,
            language: language
        ), on: cpuValue)
        cpuValue.setAccessibilityValue(cpuValue.stringValue)
        cpuValue.textColor = PopoverMetricFormatter.metricTextColor(snapshot.cpu)
        cpuSummaryValue.stringValue = PopoverMetricFormatter.summaryText(
            snapshot.cpuHistorySummary,
            language: language
        )

        memoryValue.stringValue = PopoverMetricFormatter.memoryText(snapshot.memory, language: language)
        setFailureReason(PopoverMetricFormatter.failureReason(
            snapshot.memory,
            language: language
        ), on: memoryValue)
        memoryValue.setAccessibilityValue(memoryValue.stringValue)
        memoryValue.textColor = PopoverMetricFormatter.metricTextColor(snapshot.memory)
        memorySummaryValue.stringValue = PopoverMetricFormatter.summaryText(
            snapshot.memoryHistorySummary,
            language: language
        )

        updateBatteryDetails(snapshot.battery)
        updateTemperatureField(batteryValue, state: snapshot.batteryTemperature)
        updateTemperatureField(
            batterySessionMaximumValue,
            state: snapshot.batterySessionMaximumTemperature,
            usesSeverityColor: false
        )
        updateTemperatureField(
            batteryMaximumValue,
            state: snapshot.batteryMaximumTemperature,
            usesSeverityColor: false
        )
        thermalValue.stringValue = AppText.thermalName(
            snapshot.thermalLevel,
            language: language
        )
        thermalValue.setAccessibilityValue(thermalValue.stringValue)
        thermalValue.textColor = PopoverMetricFormatter.color(
            severity: MetricPresentationPolicy.thermalSeverity(snapshot.thermalLevel)
        )
        updateNetwork(snapshot.network)
        updateDisk(snapshot.disk)
        updateHeatDiagnosis(HeatDiagnosisAnalyzer.evaluate(snapshot))

        let noBattery = PopoverMetricFormatter.isNoHardware(snapshot.battery)
        let noTemperature =
            noBattery || PopoverMetricFormatter.isNoHardware(snapshot.batteryTemperature)
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
            updatedValue.stringValue = language.localized(
                "popover.updated",
                arguments: Self.timeFormatter.string(from: latest.wallTime)
            )
        } else {
            updatedValue.stringValue = language.localized("Collecting")
        }
    }

    func setPreferences(_ preferences: PreferencesSnapshot) {
        self.preferences = preferences
        applyLocalization()
        applyDisplayPreferences()
        updateContentSize()
    }

    func popoverDidClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }

    private func applyLocalization() {
        let language = preferences.display.language
        titleLabel.stringValue = "Metrilens"
        cpuTitle.stringValue = "CPU"
        memoryTitle.stringValue = language.localized("Metrilens Memory")
        batterySectionTitle.stringValue = language.localized("Battery")
        networkSectionTitle.stringValue = language.localized("Network")
        diskSectionTitle.stringValue = language.localized("Disk")
        batteryTitle.stringValue = language.localized("Battery Temperature")
        batteryLevelTitle.stringValue = language.localized("Battery Level")
        batteryStateTitle.stringValue = language.localized("Power State")
        batteryCyclesTitle.stringValue = language.localized("Cycle Count")
        batteryHealthTitle.stringValue = language.localized("Battery Health")
        batterySessionMaximumTitle.stringValue = language.localized("Session Maximum")
        batteryMaximumTitle.stringValue = language.localized("Device Maximum")
        thermalTitle.stringValue = language.localized("Thermal State")
        networkDownloadTitle.stringValue = language.localized("Network Download")
        networkUploadTitle.stringValue = language.localized("Network Upload")
        diskUsageTitle.stringValue = language.localized("Startup Disk Used")
        diskFreeTitle.stringValue = language.localized("Startup Disk Available")
        heatDiagnosisTitle.stringValue = language.localized("Abnormal Heat Diagnosis")

        aboutButton.setAccessibilityLabel(
            language.localized("About Metrilens")
        )
        aboutButton.setAccessibilityHelp(
            language.localized("Open version and privacy-safe diagnostics")
        )
        settingsButton.setAccessibilityLabel(language.localized("Settings"))
        settingsButton.setAccessibilityHelp(
            language.localized("Open display, sampling, and alert settings")
        )
        resetSessionMaximumButton.title = language.localized("Reset")
        resetSessionMaximumButton.setAccessibilityHelp(
            language.localized("Restart the session maximum from the current temperature")
        )
        quitButton.title = language.localized("Quit")

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
        memorySparkline.metricName = language.localized("Memory")
    }

    private func applyDisplayPreferences() {
        cpuSparkline.isHidden = !preferences.sampling.showsSparkline
        memorySparkline.isHidden = !preferences.sampling.showsSparkline
        let sections: [PrimaryMetric: NSStackView] = [
            .cpu: cpuSection,
            .memory: memorySection,
            .battery: batterySection,
            .network: networkSection,
            .disk: diskSection
        ]
        metricSectionsStack.setViews(
            preferences.display.metricOrder.compactMap { sections[$0] },
            in: .top
        )
    }

    private func updateContentSize() {
        let size = NSSize(
            width: 360,
            height: preferences.sampling.showsSparkline ? 650 : 550
        )
        popover.contentSize = size
        popover.contentViewController?.preferredContentSize = size
        popover.contentViewController?.view.frame = NSRect(origin: .zero, size: size)
        layoutContentView()
    }

    private func layoutContentView() {
        guard let view = popover.contentViewController?.view else { return }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    private func updateBatteryDetails(
        _ state: MetricState<BatteryMetric>
    ) {
        guard let metric = state.value else {
            batteryHealthRow.isHidden = true
            let text = PopoverMetricFormatter.placeholder(state, language: preferences.display.language)
            let reason = PopoverMetricFormatter.failureReason(
                state,
                language: preferences.display.language
            )
            for field in [
                batteryLevelValue,
                batteryStateValue,
                batteryCyclesValue,
                batteryHealthValue
            ] {
                field.stringValue = text
                field.textColor = PopoverMetricFormatter.metricTextColor(state)
                setFailureReason(reason, on: field)
            }
            return
        }
        batteryLevelValue.stringValue = String(format: "%.0f%%", metric.levelPercent)
        batteryStateValue.stringValue = PopoverMetricFormatter.batteryPowerText(
            metric.powerState,
            language: preferences.display.language
        )
        batteryCyclesValue.stringValue = metric.cycleCount.map(String.init) ?? "—"
        batteryHealthRow.isHidden = metric.health == .unknown
        if metric.health != .unknown {
            batteryHealthValue.stringValue = PopoverMetricFormatter.batteryHealthText(
                metric.health,
                language: preferences.display.language
            )
        }
        for field in [
            batteryLevelValue,
            batteryStateValue,
            batteryCyclesValue,
            batteryHealthValue
        ] {
            field.textColor = state.isStale ? .secondaryLabelColor : .labelColor
            setFailureReason(nil, on: field)
        }
    }

    private func updateNetwork(_ state: MetricState<NetworkMetric>) {
        guard let metric = state.value else {
            let text = PopoverMetricFormatter.placeholder(state, language: preferences.display.language)
            let reason = PopoverMetricFormatter.failureReason(
                state,
                language: preferences.display.language
            )
            networkDownloadValue.stringValue = text
            networkUploadValue.stringValue = text
            setFailureReason(reason, on: networkDownloadValue)
            setFailureReason(reason, on: networkUploadValue)
            networkDownloadValue.textColor = PopoverMetricFormatter.metricTextColor(state)
            networkUploadValue.textColor = PopoverMetricFormatter.metricTextColor(state)
            return
        }
        networkDownloadValue.stringValue = PopoverMetricFormatter.rateText(
            metric.downloadBytesPerSecond
        )
        networkUploadValue.stringValue = PopoverMetricFormatter.rateText(metric.uploadBytesPerSecond)
        setFailureReason(nil, on: networkDownloadValue)
        setFailureReason(nil, on: networkUploadValue)
        networkDownloadValue.textColor = PopoverMetricFormatter.metricTextColor(state)
        networkUploadValue.textColor = PopoverMetricFormatter.metricTextColor(state)
    }

    private func updateDisk(_ state: MetricState<DiskCapacityMetric>) {
        guard let metric = state.value else {
            let text = PopoverMetricFormatter.placeholder(state, language: preferences.display.language)
            let reason = PopoverMetricFormatter.failureReason(
                state,
                language: preferences.display.language
            )
            diskUsageValue.stringValue = text
            diskFreeValue.stringValue = text
            setFailureReason(reason, on: diskUsageValue)
            setFailureReason(reason, on: diskFreeValue)
            diskUsageValue.textColor = PopoverMetricFormatter.metricTextColor(state)
            diskFreeValue.textColor = PopoverMetricFormatter.metricTextColor(state)
            return
        }
        diskUsageValue.stringValue = "\(PopoverMetricFormatter.byteText(metric.usedBytes))  "
            + String(format: "· %.0f%%", metric.usedPercent)
        diskFreeValue.stringValue = "\(PopoverMetricFormatter.byteText(metric.availableBytes))  "
            + String(format: "· %.0f%%", metric.freePercent)
        setFailureReason(nil, on: diskUsageValue)
        setFailureReason(nil, on: diskFreeValue)
        let severity: MetricVisualSeverity =
            metric.freePercent <= 5 ? .warning
            : metric.freePercent <= 10 ? .caution
            : .normal
        diskUsageValue.textColor = PopoverMetricFormatter.metricTextColor(state)
        diskFreeValue.textColor = state.isStale
            ? .secondaryLabelColor
            : PopoverMetricFormatter.color(severity: severity)
    }

    private func updateHeatDiagnosis(_ diagnosis: HeatDiagnosis) {
        let language = preferences.display.language
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
                language.localized("Metrilens does not scan processes; confirm the source in Activity Monitor.")
            )
        }
        heatDiagnosisValue.stringValue = lines.joined(separator: "\n")
        heatDiagnosisTitle.isHidden = !diagnosis.isAbnormal
        heatDiagnosisValue.isHidden = !diagnosis.isAbnormal
        heatDiagnosisValue.textColor = diagnosis.severity == .urgent
            ? .systemRed
            : diagnosis.severity == .elevated
                ? .systemOrange
                : .secondaryLabelColor
    }

    private func updateTemperatureField(
        _ field: NSTextField,
        state: MetricState<Double>,
        usesSeverityColor: Bool = true
    ) {
        field.stringValue = PopoverMetricFormatter.temperatureText(
            state,
            language: preferences.display.language
        )
        field.setAccessibilityValue(field.stringValue)
        setFailureReason(PopoverMetricFormatter.failureReason(
            state,
            language: preferences.display.language
        ), on: field)
        field.textColor = usesSeverityColor
            ? PopoverMetricFormatter.temperatureTextColor(state)
            : PopoverMetricFormatter.metricTextColor(state)
    }

    private func setFailureReason(_ reason: String?, on field: NSTextField) {
        field.toolTip = reason
        field.setAccessibilityHelp(reason)
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
