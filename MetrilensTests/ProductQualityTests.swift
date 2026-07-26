import XCTest
@testable import Metrilens

final class ProductQualityTests: XCTestCase {
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

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.snapshot,
            PreferencesSnapshot(
                primaryMetric: .cpu,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: true
            )
        )
        let persistent = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertNil(persistent["primaryMetric"])
        XCTAssertNil(persistent["refreshInterval"])
        XCTAssertNil(persistent["launchAtLogin"])
        XCTAssertNil(persistent["showsSparkline"])
    }

    func testResetPreferencesRestoresEveryDefaultAndNotifiesOnce() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.setPrimaryMetric(.battery)
        preferences.setRefreshInterval(5)
        preferences.setLaunchAtLogin(true)
        preferences.setShowsSparkline(false)

        var notifications = 0
        preferences.onChange = { _ in notifications += 1 }
        preferences.resetToDefaults()

        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(
            preferences.snapshot,
            PreferencesSnapshot(
                primaryMetric: .cpu,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: true
            )
        )
    }

    func testBooleanStoredAsRefreshIntervalIsRejected() {
        defaults.set(true, forKey: "refreshInterval")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.snapshot.refreshInterval, 1)
        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?["refreshInterval"]
        )
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
                primaryMetric: .cpu,
                refreshInterval: 2,
                launchAtLogin: false,
                showsSparkline: true
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
            "settings.refresh_seconds=",
            "settings.launch_at_login=",
            "settings.sparkline=",
            "metrics.cpu=",
            "metrics.memory=",
            "metrics.battery_temperature=",
            "metrics.battery_maximum=",
            "metrics.thermal="
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
            "process_id"
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
            "指标状态"
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
            showsSparkline: true,
            keyboardFocusHandler: { _ in focusRequests += 1 }
        )

        controller.focusKeyboardInput()

        XCTAssertEqual(focusRequests, 1)
    }
}
