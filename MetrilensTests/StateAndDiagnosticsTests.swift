import XCTest
import AppKit
@testable import Metrilens

final class StateAndDiagnosticsTests: XCTestCase {
    func testTaskPowerInfoIsAvailableOnCurrentSDKAndMac() throws {
        guard case let .success(snapshot) = TaskPowerProbe.readCurrentTask() else {
            return XCTFail("TASK_POWER_INFO is unavailable")
        }
        XCTAssertGreaterThanOrEqual(snapshot.interruptWakeups, 0)
    }

    func testMetricStateTransitionsThroughStaleAndUnavailable() {
        let machine = MetricStateMachine<Int>()
        _ = machine.recordSuccess(42, stamp: SampleStamp(wallTime: Date(), uptime: 10))

        guard case let .stale(value, _) = machine.recordFailure(
            .machFailure(1),
            nowUptime: 11,
            failureLimit: 3,
            ttl: 10
        ) else {
            return XCTFail("Expected stale")
        }
        XCTAssertEqual(value, 42)

        _ = machine.recordFailure(.machFailure(1), nowUptime: 12, failureLimit: 3, ttl: 10)
        guard case .unavailable(.machFailure(1)) = machine.recordFailure(
            .machFailure(1),
            nowUptime: 13,
            failureLimit: 3,
            ttl: 10
        ) else {
            return XCTFail("Expected unavailable")
        }
    }

    func testFailedStaleValueExpiresWithoutAnotherRead() {
        let machine = MetricStateMachine<Int>()
        _ = machine.recordSuccess(42, stamp: SampleStamp(wallTime: Date(), uptime: 10))
        _ = machine.recordFailure(.machFailure(1), nowUptime: 11, failureLimit: 3, ttl: 10)
        guard case .unavailable(.machFailure(1)) = machine.expireFailedValueIfNeeded(
            nowUptime: 20,
            ttl: 10
        ) else {
            return XCTFail("Expected stale value to expire")
        }
    }

    func testPausePreservesOnlyFreshCacheAsStale() {
        let machine = MetricStateMachine<Int>()
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        _ = machine.recordSuccess(42, stamp: stamp)
        guard case let .stale(value, _) = machine.preserveFreshValueAsStale(
            nowUptime: 15,
            ttl: 10
        ) else {
            return XCTFail("Fresh cache should become stale")
        }
        XCTAssertEqual(value, 42)
        guard case .unavailable = machine.expireFailedValueIfNeeded(
            nowUptime: 20,
            ttl: 10
        ) else {
            return XCTFail("Expired paused cache must be discarded")
        }
    }

    func testMetricTextColorMarksOnlyStaleValuesAsSecondary() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 1)
        XCTAssertTrue(
            PopoverController.metricTextColor(
                MetricState<Double>.stale(35, stamp)
            ).isEqual(NSColor.secondaryLabelColor)
        )
        XCTAssertTrue(
            PopoverController.metricTextColor(
                MetricState<Double>.available(35, stamp)
            ).isEqual(NSColor.labelColor)
        )
        XCTAssertTrue(
            PopoverController.metricTextColor(
                MetricState<Double>.unavailable(.fieldMissing)
            ).isEqual(NSColor.labelColor)
        )
    }

    func testStatusItemColorUsesNativeSelectionAndMutedCaution() {
        XCTAssertTrue(
            StatusItemController.statusColor(
                severity: .caution,
                stale: false,
                selected: true
            ).isEqual(NSColor.selectedMenuItemTextColor)
        )

        let caution = StatusItemController.statusColor(
            severity: .caution,
            stale: false,
            selected: false
        )
        XCTAssertFalse(caution.isEqual(NSColor.systemYellow))
        XCTAssertEqual(caution.alphaComponent, 0.72, accuracy: 0.001)
    }

    func testStatusItemSelectionPreservesAccessibilityWarnings() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .stale(CPUMetric(percent: 66), stamp)
        snapshot.thermalLevel = .serious
        let controller = StatusItemController(
            preferences: PreferencesSnapshot(
                primaryMetric: .cpu,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: true,
                language: .simplifiedChinese
            )
        )

        controller.update(snapshot: snapshot)
        let warningValue = controller.accessibilityValueForTesting()
        XCTAssertTrue(warningValue?.contains("数据已过期") == true)
        XCTAssertTrue(warningValue?.contains("系统热状态警告") == true)
        XCTAssertFalse(controller.isHighlightedForTesting())

        controller.setPopoverVisible(true)
        XCTAssertTrue(controller.isHighlightedForTesting())
        XCTAssertEqual(controller.accessibilityValueForTesting(), warningValue)
        controller.setPopoverVisible(false)
        XCTAssertFalse(controller.isHighlightedForTesting())
        XCTAssertEqual(controller.accessibilityValueForTesting(), warningValue)
    }

    func testStatusItemPresentationsMarkAllStalePrimaryMetrics() {
        let stamp = SampleStamp(wallTime: Date(timeIntervalSince1970: 100), uptime: 100)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .stale(CPUMetric(percent: 20), stamp)
        snapshot.memory = .stale(
            MemoryMetric(usedBytes: 20, totalBytes: 100, availableBytes: 80, purgeableBytes: 0),
            stamp
        )
        snapshot.batteryTemperature = .stale(35, stamp)
        snapshot.network = .stale(
            NetworkMetric(
                downloadBytesPerSecond: 1_000,
                uploadBytesPerSecond: 500,
                interfaceName: "en0"
            ),
            stamp
        )
        snapshot.disk = .stale(
            DiskCapacityMetric(
                totalBytes: 100,
                freeBytes: 40,
                availableBytes: 30
            ),
            stamp
        )

        for metric in PrimaryMetric.allCases {
            let presentation = StatusItemController.presentation(
                primaryMetric: metric,
                snapshot: snapshot
            )
            XCTAssertTrue(presentation.title.hasSuffix(" ⏱"))
            XCTAssertEqual(presentation.staleStamps, [stamp])
        }
    }

    func testStaleDiskAndTemperatureStopContributingAlertSeverity() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        let lowDisk = DiskCapacityMetric(
            totalBytes: 100,
            freeBytes: 4,
            availableBytes: 4
        )

        snapshot.disk = .available(lowDisk, stamp)
        XCTAssertEqual(
            StatusItemController.presentation(
                primaryMetric: .disk,
                snapshot: snapshot
            ).severity,
            .warning
        )

        snapshot.disk = .stale(lowDisk, stamp)
        let staleDisk = StatusItemController.presentation(
            primaryMetric: .disk,
            snapshot: snapshot
        )
        XCTAssertEqual(staleDisk.severity, .normal)
        XCTAssertEqual(staleDisk.staleStamps, [stamp])

        snapshot.batteryTemperature = .stale(46, stamp)
        XCTAssertEqual(
            StatusItemController.presentation(
                primaryMetric: .battery,
                snapshot: snapshot
            ).severity,
            .normal
        )
    }

    func testCompactStatusItemCombinesSelectedMetricsAndHighestSeverity() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 23), stamp)
        snapshot.memory = .available(
            MemoryMetric(
                usedBytes: 72,
                totalBytes: 100,
                availableBytes: 28,
                purgeableBytes: 0
            ),
            stamp
        )
        snapshot.batteryTemperature = .available(43, stamp)
        let preferences = PreferencesSnapshot(
            primaryMetric: .cpu,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true,
            statusDisplayMode: .compact,
            compactMetrics: [.cpu, .memory, .battery],
            language: .simplifiedChinese
        )

        let presentation = StatusItemController.presentation(
            preferences: preferences,
            snapshot: snapshot
        )

        XCTAssertEqual(presentation.title, "CPU 23% · 内存 72% · 电池 43.0°C")
        XCTAssertEqual(presentation.staleStamps, [])
        XCTAssertEqual(presentation.severity, .warning)
    }

    func testCompactStatusItemUsesClearEnglishMetricNames() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.memory = .available(
            MemoryMetric(
                usedBytes: 72,
                totalBytes: 100,
                availableBytes: 28,
                purgeableBytes: 0
            ),
            stamp
        )
        snapshot.batteryTemperature = .available(43, stamp)
        snapshot.disk = .available(
            DiskCapacityMetric(
                totalBytes: 100,
                freeBytes: 40,
                availableBytes: 35
            ),
            stamp
        )
        let preferences = PreferencesSnapshot(
            primaryMetric: .memory,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true,
            statusDisplayMode: .compact,
            compactMetrics: [.memory, .battery, .disk],
            statusDecimalPlaces: 1,
            language: .english
        )

        XCTAssertEqual(
            StatusItemController.presentation(
                preferences: preferences,
                snapshot: snapshot
            ).title,
            "RAM 72.0% · Batt 43.0°C · Free 35.0%"
        )
    }

    func testAvailableNetworkStatusItemUsesLocalizedMetricName() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.network = .available(
            NetworkMetric(
                downloadBytesPerSecond: 1_200,
                uploadBytesPerSecond: 300,
                interfaceName: "en0"
            ),
            stamp
        )

        func presentation(language: AppLanguage) -> StatusMetricPresentation {
            StatusItemController.presentation(
                preferences: PreferencesSnapshot(
                    primaryMetric: .network,
                    refreshInterval: 1,
                    launchAtLogin: false,
                    showsSparkline: true,
                    statusDecimalPlaces: 1,
                    language: language
                ),
                snapshot: snapshot
            )
        }

        XCTAssertEqual(
            presentation(language: .simplifiedChinese).title,
            "网络 ↓1.2K/s ↑300.0B/s"
        )
        XCTAssertEqual(
            presentation(language: .english).title,
            "Net ↓1.2K/s ↑300.0B/s"
        )
    }

    func testSparklineFindsNearestPointAcrossUnevenSamples() {
        let points = [
            MetricHistoryPoint(uptime: 10, percent: 10),
            MetricHistoryPoint(uptime: 20, percent: 20),
            MetricHistoryPoint(uptime: 50, percent: 50)
        ]

        XCTAssertEqual(
            SparklineView.nearestPoint(toNormalizedX: 0.3, points: points),
            points[1]
        )
        XCTAssertEqual(
            SparklineView.nearestPoint(toNormalizedX: 2, points: points),
            points[2]
        )
    }

    func testSettingsExplainTheMemoryProductDefinition() {
        XCTAssertTrue(PreferencesController.sourceInformation.contains("internal"))
        XCTAssertTrue(PreferencesController.sourceInformation.contains("wired"))
        XCTAssertTrue(PreferencesController.sourceInformation.contains("compressor"))
        XCTAssertTrue(PreferencesController.sourceInformation.contains("活动监视器"))
    }

    func testSystemEventCoalescerDoesNotExtendWindowForRejectedEvents() {
        var coalescer = SystemEventCoalescer(window: 2)
        XCTAssertTrue(coalescer.shouldAccept(at: 100))
        XCTAssertFalse(coalescer.shouldAccept(at: 101))
        XCTAssertTrue(coalescer.shouldAccept(at: 102))
    }

    func testTaskPowerRate() {
        let start = TaskPowerSnapshot(
            interruptWakeups: 100,
            platformIdleWakeups: 5,
            timerWakeupsBin1: 1,
            timerWakeupsBin2: 2
        )
        let end = TaskPowerSnapshot(
            interruptWakeups: 220,
            platformIdleWakeups: 8,
            timerWakeupsBin1: 4,
            timerWakeupsBin2: 5
        )
        guard case let .success(rate) = TaskPowerProbe.calculateRate(
            start: start,
            end: end,
            elapsed: 100
        ) else {
            return XCTFail("Expected rate")
        }
        XCTAssertEqual(rate, 1.2, accuracy: 0.0001)
    }

    func testTaskPowerRequestedStartMustBeFutureAndFinite() {
        XCTAssertEqual(
            TaskPowerProbe.validatedRequestedStartUptime("101.5", nowUptime: 100),
            101.5
        )
        XCTAssertNil(
            TaskPowerProbe.validatedRequestedStartUptime("100", nowUptime: 100)
        )
        XCTAssertNil(
            TaskPowerProbe.validatedRequestedStartUptime("nan", nowUptime: 100)
        )
        XCTAssertNil(
            TaskPowerProbe.validatedRequestedStartUptime(nil, nowUptime: 100)
        )
    }

    func testTaskPowerSnapshotReadMustFitInsideEndpointTolerance() {
        let snapshot = TaskPowerSnapshot(
            interruptWakeups: 100,
            platformIdleWakeups: 5,
            timerWakeupsBin1: 1,
            timerWakeupsBin2: 2
        )
        var validTimes = [100.0, 100.02].makeIterator()
        guard case let .success(valid) = TaskPowerProbe.readTimedCurrentTask(
            clock: { validTimes.next()! },
            reader: { .success(snapshot) }
        ) else {
            return XCTFail("Expected timed snapshot")
        }
        XCTAssertTrue(
            TaskPowerProbe.endpointContainsSnapshot(
                valid,
                expectedUptime: 100.01
            )
        )
        XCTAssertEqual(valid.midpointUptime, 100.01, accuracy: 0.000_001)

        var overlongTimes = [100.0, 100.2].makeIterator()
        guard case let .success(overlong) = TaskPowerProbe.readTimedCurrentTask(
            clock: { overlongTimes.next()! },
            reader: { .success(snapshot) }
        ) else {
            return XCTFail("Expected timed snapshot")
        }
        XCTAssertFalse(
            TaskPowerProbe.endpointContainsSnapshot(
                overlong,
                expectedUptime: 100.1
            )
        )
    }

    func testTaskPowerRejectsResetAndInvalidDuration() {
        let high = TaskPowerSnapshot(
            interruptWakeups: 200,
            platformIdleWakeups: 0,
            timerWakeupsBin1: 0,
            timerWakeupsBin2: 0
        )
        let low = TaskPowerSnapshot(
            interruptWakeups: 100,
            platformIdleWakeups: 0,
            timerWakeupsBin1: 0,
            timerWakeupsBin2: 0
        )
        guard case .failure(.counterReset) = TaskPowerProbe.calculateRate(
            start: high,
            end: low,
            elapsed: 10
        ) else {
            return XCTFail("Expected counterReset")
        }
        guard case .failure(.invalidDuration) = TaskPowerProbe.calculateRate(
            start: low,
            end: high,
            elapsed: 0
        ) else {
            return XCTFail("Expected invalidDuration")
        }
    }
}
