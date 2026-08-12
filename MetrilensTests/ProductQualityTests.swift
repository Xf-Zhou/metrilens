import XCTest
@testable import Metrilens

final class ProductQualityTests: XCTestCase {
    func testLocalizationCatalogHasCompleteFormats() {
        XCTAssertGreaterThan(AppTextCatalog.keys.count, 100)
        XCTAssertEqual(AppTextCatalog.validationFailures, [])
    }

    func testNotificationStatusRefreshPreservesMetricOrderSelection() {
        let form = PreferencesForm()
        let snapshot = PreferencesSnapshot()
        form.render(
            snapshot: snapshot,
            loginItemEnabled: false,
            notificationState: .unknown
        )
        form.metricOrderPopup.selectItem(at: 3)

        form.updateNotificationStatus(
            .authorized,
            language: snapshot.display.language
        )

        XCTAssertEqual(form.metricOrderPopup.indexOfSelectedItem, 3)
    }

    func testMissingBuildInformationUsesLocalizedUnknownText() {
        let build = AppBuildInformation(version: nil, build: nil)

        XCTAssertEqual(
            AboutController.versionText(build: build, language: .english),
            "Version Unknown (Unknown)"
        )
        XCTAssertEqual(
            AboutController.versionText(build: build, language: .simplifiedChinese),
            "版本 未知（未知）"
        )
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MetrilensTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCorruptedPreferencesRecoverToSafeDefaults() {
        defaults.set("gpu", forKey: "primaryMetric")
        defaults.set(3.0, forKey: "refreshInterval")
        defaults.set("yes", forKey: "launchAtLogin")
        defaults.set(["unexpected"], forKey: "showsSparkline")
        defaults.set("wide", forKey: "statusDisplayMode")
        defaults.set(["cpu", "cpu"], forKey: "compactMetrics")
        defaults.set(["cpu"], forKey: "metricOrder")
        defaults.set("comma", forKey: "statusSeparator")
        defaults.set(3, forKey: "statusDecimalPlaces")
        defaults.set("fr", forKey: "language")
        defaults.set("yes", forKey: "alertsEnabled")
        defaults.set(87, forKey: "cpuAlertThreshold")
        defaults.set(true, forKey: "memoryAlertThreshold")
        defaults.set(15, forKey: "alertSustainDuration")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.snapshot,
            PreferencesSnapshot()
        )
        let persistent = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertNil(persistent["primaryMetric"])
        XCTAssertNil(persistent["refreshInterval"])
        XCTAssertNil(persistent["launchAtLogin"])
        XCTAssertNil(persistent["showsSparkline"])
        XCTAssertNil(persistent["statusDisplayMode"])
        XCTAssertNil(persistent["compactMetrics"])
        XCTAssertNil(persistent["metricOrder"])
        XCTAssertNil(persistent["statusSeparator"])
        XCTAssertNil(persistent["statusDecimalPlaces"])
        XCTAssertNil(persistent["language"])
        XCTAssertNil(persistent["alertsEnabled"])
        XCTAssertNil(persistent["cpuAlertThreshold"])
        XCTAssertNil(persistent["memoryAlertThreshold"])
        XCTAssertNil(persistent["alertSustainDuration"])
    }

    func testResetPreferencesRestoresEveryDefaultAndNotifiesOnce() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.updateDisplay {
            $0.primaryMetric = .battery
            $0.statusDisplayMode = .compact
            $0.compactMetrics = [.memory]
            $0.metricOrder = [.disk, .network, .battery, .memory, .cpu]
            $0.statusSeparator = .bar
            $0.statusDecimalPlaces = 1
            $0.language = .english
        }
        preferences.updateSampling {
            $0.refreshInterval = 5
            $0.showsSparkline = false
        }
        preferences.updateSystem { $0.launchAtLogin = true }
        preferences.updateAlerts {
            $0.enabled = true
            $0.thresholds.cpu = 95
            $0.thresholds.memory = 80
            $0.sustainDuration = 120
        }

        var notifications = 0
        preferences.onChange = { _ in notifications += 1 }
        preferences.resetToDefaults()

        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(
            preferences.snapshot,
            PreferencesSnapshot()
        )
    }

    func testBooleanStoredAsRefreshIntervalIsRejected() {
        defaults.set(true, forKey: "refreshInterval")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.snapshot.sampling.refreshInterval, 1)
        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?["refreshInterval"]
        )
    }

    func testTenAndThirtySecondRefreshIntervalsAreAccepted() {
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(
            AppPreferences.allowedRefreshIntervals,
            [1, 2, 5, 10, 30]
        )

        preferences.updateSampling { $0.refreshInterval = 10 }
        XCTAssertEqual(preferences.snapshot.sampling.refreshInterval, 10)

        preferences.updateSampling { $0.refreshInterval = 30 }
        XCTAssertEqual(preferences.snapshot.sampling.refreshInterval, 30)
    }

    func testDiagnosticReportHasOnlyWhitelistedPrivacySafeFields() {
        let stamp = SampleStamp(
            wallTime: Date(timeIntervalSince1970: 1_000),
            uptime: 1_000
        )
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 12.5), stamp)
        snapshot.memory = .stale(
            MemoryMetric(
                usedBytes: 25,
                totalBytes: 100,
                availableBytes: 75,
                purgeableBytes: 0
            ),
            stamp
        )
        snapshot.batteryTemperature = .unsupported(.noHardware)
        snapshot.batteryMaximumTemperature = .unsupported(.noHardware)

        let report = DiagnosticReport.make(
            build: AppBuildInformation(version: "0.2.0", build: "1"),
            context: DiagnosticContext(
                operatingSystem: "macOS 15.5",
                architecture: "arm64",
                lowPowerModeEnabled: false
            ),
            preferences: PreferencesSnapshot(
                display: DisplaySettings(language: .simplifiedChinese),
                sampling: SamplingSettings(refreshInterval: 2)
            ),
            snapshot: snapshot
        )

        let allowedPrefixes = [
            "Metrilens 诊断信息",
            "app.version=",
            "app.build=",
            "system.os=",
            "system.arch=",
            "system.low_power=",
            "settings.primary_metric=",
            "settings.display_mode=",
            "settings.compact_metrics=",
            "settings.metric_order=",
            "settings.status_separator=",
            "settings.status_decimals=",
            "settings.refresh_seconds=",
            "settings.launch_at_login=",
            "settings.sparkline=",
            "settings.language=",
            "settings.alerts_enabled=",
            "settings.cpu_alert_enabled=",
            "settings.memory_alert_enabled=",
            "settings.thermal_alert_enabled=",
            "settings.battery_level_alert_enabled=",
            "settings.battery_temperature_alert_enabled=",
            "settings.disk_free_alert_enabled=",
            "settings.cpu_alert_threshold=",
            "settings.memory_alert_threshold=",
            "settings.battery_level_alert_threshold=",
            "settings.battery_temperature_alert_threshold=",
            "settings.disk_free_alert_threshold=",
            "settings.alert_sustain_seconds=",
            "sampling.running=",
            "sampling.sleeping=",
            "sampling.popover_visible=",
            "sampling.cpu_period=",
            "sampling.memory_period=",
            "sampling.battery_period=",
            "sampling.network_period=",
            "sampling.disk_period=",
            "metrics.cpu=",
            "metrics.cpu_average=",
            "metrics.cpu_peak=",
            "metrics.memory=",
            "metrics.memory_average=",
            "metrics.memory_peak=",
            "metrics.battery_temperature=",
            "metrics.battery_level=",
            "metrics.battery_power=",
            "metrics.battery_cycles=",
            "metrics.battery_health=",
            "metrics.battery_session_maximum=",
            "metrics.battery_maximum=",
            "metrics.network_download=",
            "metrics.network_upload=",
            "metrics.disk_used=",
            "metrics.disk_free=",
            "metrics.thermal=",
            "heat.severity=",
            "heat.evidence=",
            "heat.recommendations=",
            "metrics.recent_errors="
        ]
        let lines = report.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, allowedPrefixes.count)
        for (line, prefix) in zip(lines, allowedPrefixes) {
            XCTAssertTrue(line.hasPrefix(prefix), "Unexpected diagnostic line: \(line)")
        }
        for forbidden in [
            "username",
            "user_name",
            "hostname",
            "host_name",
            "serial",
            "home_directory",
            "ip_address",
            "process_id",
            "path=",
            "pid="
        ] {
            XCTAssertFalse(report.localizedCaseInsensitiveContains(forbidden))
        }

        let disclosure = DiagnosticReport.privacyDisclosure
        for disclosedField in [
            "App 版本与构建号",
            "macOS 版本",
            "系统架构",
            "低电量模式状态",
            "应用设置",
            "采样状态",
            "指标状态",
            "最近的指标读取错误"
        ] {
            XCTAssertTrue(
                disclosure.contains(disclosedField),
                "Missing diagnostic disclosure: \(disclosedField)"
            )
        }
    }

    func testPopoverKeyboardFocusInvokesConfiguredHandler() {
        var focusRequests = 0
        let controller = PopoverController(
            preferences: PreferencesSnapshot(),
            keyboardFocusHandler: { _ in focusRequests += 1 }
        )

        controller.focusKeyboardInput()

        XCTAssertEqual(focusRequests, 1)
    }

    func testPopoverScrollsWhenMaximumHeatDiagnosisExceedsViewport() throws {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 95), stamp)
        snapshot.cpuHistorySummary = MetricHistorySummary(
            average: 90,
            peak: 100
        )
        snapshot.battery = .available(
            BatteryMetric(
                levelPercent: 70,
                powerState: .charging,
                cycleCount: 200,
                health: .good,
                timeRemainingMinutes: 30
            ),
            stamp
        )
        snapshot.batteryTemperature = .available(47, stamp)
        snapshot.thermalLevel = .critical
        let controller = PopoverController(
            preferences: PreferencesSnapshot(
                display: DisplaySettings(language: .english)
            )
        )

        controller.update(snapshot: snapshot)
        let layout = controller.layoutStateForTesting()

        XCTAssertGreaterThan(layout.viewportHeight, 0)
        XCTAssertTrue(layout.scrollable)
        XCTAssertGreaterThan(layout.contentHeight, layout.viewportHeight)

        let stack = try XCTUnwrap(controller.contentStack)
        let document = try XCTUnwrap(controller.contentScrollView.documentView)
        XCTAssertEqual(stack.frame.minX, 16, accuracy: 0.001)
        XCTAssertEqual(
            document.bounds.width - stack.frame.maxX,
            16,
            accuracy: 0.001
        )
    }

    func testPreferencesInitiallyShowsTopOfFlippedDocument() {
        let controller = PreferencesController(
            preferences: AppPreferences(defaults: defaults),
            loginItemController: LoginItemController()
        )

        let scroll = controller.initialScrollStateForTesting()

        XCTAssertTrue(scroll.documentIsFlipped)
        XCTAssertEqual(scroll.visibleMinY, 0, accuracy: 0.001)
        XCTAssertTrue(scroll.languageControlVisible)
    }

    func testPopoverHidesWholeBatterySectionOnlyWhenBatteryIsAbsent() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        let controller = PopoverController(
            preferences: PreferencesSnapshot(
                sampling: SamplingSettings(showsSparkline: false)
            )
        )
        var snapshot = SystemSnapshot.initial()
        snapshot.battery = .unsupported(.noHardware)
        snapshot.batteryTemperature = .unsupported(.noHardware)

        controller.update(snapshot: snapshot)
        var visibility = controller.batteryVisibilityForTesting()
        XCTAssertTrue(visibility.sectionHidden)
        XCTAssertTrue(visibility.temperatureRowsHidden)

        snapshot.battery = .available(
            BatteryMetric(
                levelPercent: 80,
                powerState: .discharging,
                cycleCount: 100,
                health: .good,
                timeRemainingMinutes: 180
            ),
            stamp
        )
        controller.update(snapshot: snapshot)
        visibility = controller.batteryVisibilityForTesting()
        XCTAssertFalse(visibility.sectionHidden)
        XCTAssertTrue(visibility.temperatureRowsHidden)
    }

    func testPopoverHidesUnknownBatteryHealthAndRestoresKnownHealth() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        let controller = PopoverController(
            preferences: PreferencesSnapshot(
                sampling: SamplingSettings(showsSparkline: false)
            )
        )
        var snapshot = SystemSnapshot.initial()
        snapshot.battery = .available(
            BatteryMetric(
                levelPercent: 93,
                powerState: .externalPower,
                cycleCount: 167,
                health: .unknown,
                timeRemainingMinutes: nil
            ),
            stamp
        )

        controller.update(snapshot: snapshot)
        XCTAssertTrue(controller.batteryHealthRowHiddenForTesting())

        snapshot.battery = .available(
            BatteryMetric(
                levelPercent: 93,
                powerState: .externalPower,
                cycleCount: 167,
                health: .good,
                timeRemainingMinutes: nil
            ),
            stamp
        )
        controller.update(snapshot: snapshot)
        XCTAssertFalse(controller.batteryHealthRowHiddenForTesting())

        snapshot.battery = .unavailable(.fieldMissing)
        controller.update(snapshot: snapshot)
        XCTAssertTrue(controller.batteryHealthRowHiddenForTesting())
    }

    func testDiskPlaceholderClearsPreviousSeverityColor() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        let controller = PopoverController(
            preferences: PreferencesSnapshot(
                display: DisplaySettings(language: .simplifiedChinese),
                sampling: SamplingSettings(showsSparkline: false)
            )
        )
        var snapshot = SystemSnapshot.initial()
        snapshot.disk = .available(
            DiskCapacityMetric(
                totalBytes: 100,
                freeBytes: 4,
                availableBytes: 4
            ),
            stamp
        )

        controller.update(snapshot: snapshot)
        XCTAssertTrue(
            controller.diskPresentationForTesting().freeColor.isEqual(
                NSColor.systemOrange
            )
        )

        snapshot.disk = .unavailable(.fieldMissing)
        controller.update(snapshot: snapshot)
        let presentation = controller.diskPresentationForTesting()

        XCTAssertEqual(presentation.usedText, "系统未提供该字段")
        XCTAssertEqual(presentation.freeText, "系统未提供该字段")
        XCTAssertTrue(presentation.usedColor.isEqual(NSColor.labelColor))
        XCTAssertTrue(presentation.freeColor.isEqual(NSColor.labelColor))
    }

    func testNetworkPlaceholderClearsStaleTextColor() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        let controller = PopoverController(
            preferences: PreferencesSnapshot(
                display: DisplaySettings(
                    primaryMetric: .network,
                    language: .simplifiedChinese
                ),
                sampling: SamplingSettings(showsSparkline: false)
            )
        )
        var snapshot = SystemSnapshot.initial()
        snapshot.network = .stale(
            NetworkMetric(
                downloadBytesPerSecond: 1_000,
                uploadBytesPerSecond: 500,
                interfaceName: "en0"
            ),
            stamp
        )

        controller.update(snapshot: snapshot)
        var presentation = controller.networkPresentationForTesting()
        XCTAssertTrue(
            presentation.downloadColor.isEqual(NSColor.secondaryLabelColor)
        )
        XCTAssertTrue(
            presentation.uploadColor.isEqual(NSColor.secondaryLabelColor)
        )

        snapshot.network = .unavailable(.fieldMissing)
        controller.update(snapshot: snapshot)
        presentation = controller.networkPresentationForTesting()

        XCTAssertEqual(presentation.downloadText, "系统未提供该字段")
        XCTAssertEqual(presentation.uploadText, "系统未提供该字段")
        XCTAssertTrue(presentation.downloadColor.isEqual(NSColor.labelColor))
        XCTAssertTrue(presentation.uploadColor.isEqual(NSColor.labelColor))
    }

    func testEnglishLocalizationAndDiagnosticFilename() {
        XCTAssertEqual(AppText.metricName(.memory, language: .english), "Memory")
        XCTAssertEqual(
            AppText.failureReason(.noHardware, language: .english),
            "No Battery"
        )
        XCTAssertTrue(
            DiagnosticReport.privacyDisclosure(language: .english)
                .contains("do not include usernames")
        )

        let filename = AboutController.diagnosticFilename(
            date: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertTrue(filename.hasPrefix("Metrilens-Diagnostics-"))
        XCTAssertTrue(filename.hasSuffix(".txt"))
        XCTAssertFalse(filename.contains("/"))
    }
}
