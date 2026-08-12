import Darwin
import SystemConfiguration
import XCTest
@testable import Metrilens

final class SystemMetricProviderTests: XCTestCase {
    func testBatteryStatusDecodesChargeCyclesAndHealth() throws {
        let result = BatteryStatusProvider.decode([
            "CurrentCapacity": 4_000,
            "MaxCapacity": 5_000,
            "IsCharging": true,
            "ExternalConnected": true,
            "CycleCount": 321,
            "BatteryHealth": "Good",
            "AvgTimeToFull": 45
        ])
        let metric = try result.get()

        XCTAssertEqual(metric.levelPercent, 80, accuracy: 0.001)
        XCTAssertEqual(metric.powerState, .charging)
        XCTAssertEqual(metric.cycleCount, 321)
        XCTAssertEqual(metric.health, .good)
        XCTAssertEqual(metric.timeRemainingMinutes, 45)
    }

    func testBatteryStatusFallsBackFromEmptyConditionToHealthEstimate() throws {
        let result = BatteryStatusProvider.decode([
            "CurrentCapacity": 92,
            "MaxCapacity": 100,
            "BatteryHealthCondition": "  \n",
            "BatteryHealth": "Good"
        ])

        XCTAssertEqual(try result.get().health, .good)
    }

    func testBatteryStatusDoesNotMaskUnknownNonEmptyCondition() throws {
        let result = BatteryStatusProvider.decode([
            "CurrentCapacity": 92,
            "MaxCapacity": 100,
            "BatteryHealthCondition": "New Hardware Warning",
            "BatteryHealth": "Good",
            "PermanentFailureStatus": 0
        ])

        XCTAssertEqual(try result.get().health, .unknown)
    }

    func testBatteryStatusRecognizesOfficialPermanentFailureValue() throws {
        let result = BatteryStatusProvider.decode([
            "CurrentCapacity": 50,
            "MaxCapacity": 100,
            "BatteryHealthCondition": "Permanent Battery Failure",
            "BatteryHealth": "Good"
        ])

        XCTAssertEqual(try result.get().health, .serviceRecommended)
    }

    func testBatteryStatusRecognizesOfficialCheckBatteryCondition() throws {
        let result = BatteryStatusProvider.decode([
            "CurrentCapacity": 94,
            "MaxCapacity": 100,
            "BatteryHealthCondition": "Check Battery",
            "BatteryHealth": "Good"
        ])

        XCTAssertEqual(try result.get().health, .serviceRecommended)
    }

    func testBatteryStatusIgnoresConditionValueInHealthEstimate() throws {
        let result = BatteryStatusProvider.decode([
            "CurrentCapacity": 94,
            "MaxCapacity": 100,
            "BatteryHealthCondition": "",
            "BatteryHealth": "Check Battery",
            "PermanentFailureStatus": 0
        ])

        XCTAssertEqual(try result.get().health, .unknown)
    }

    func testBatteryStatusRecognizesPermanentFailureStatus() throws {
        let result = BatteryStatusProvider.decode([
            "CurrentCapacity": 94,
            "MaxCapacity": 100,
            "BatteryHealthCondition": "",
            "BatteryHealth": "Check Battery",
            "PermanentFailureStatus": 1
        ])

        XCTAssertEqual(try result.get().health, .serviceRecommended)
    }

    func testBatteryStatusRejectsMissingCapacity() {
        guard case .failure(.fieldMissing) = BatteryStatusProvider.decode([
            "CurrentCapacity": 100
        ]) else {
            return XCTFail("Missing maximum capacity must not be guessed")
        }
    }

    func testBatteryStatusRejectsCapacityWhoseAllowanceWouldOverflow() {
        guard case .failure(.outOfRange) = BatteryStatusProvider.decode([
            "CurrentCapacity": Int64(1),
            "MaxCapacity": Int64.max
        ]) else {
            return XCTFail("Extreme capacity must be rejected without overflow")
        }
    }

    func testNetworkProviderUsesMonotonicCounterDeltaAndResetsInterface() {
        var samples = [
            NetworkCounters(
                interfaceName: "en0",
                receivedBytes: 1_000,
                sentBytes: 2_000,
                uptime: 10
            ),
            NetworkCounters(
                interfaceName: "en0",
                receivedBytes: 3_000,
                sentBytes: 3_000,
                uptime: 12
            ),
            NetworkCounters(
                interfaceName: "en1",
                receivedBytes: 10,
                sentBytes: 20,
                uptime: 13
            )
        ].makeIterator()
        let provider = NetworkProvider {
            .success(samples.next()!)
        }

        XCTAssertNil(provider.sample(period: 1).value)
        let metric = provider.sample(period: 1).freshValue
        XCTAssertEqual(metric?.downloadBytesPerSecond, 1_000)
        XCTAssertEqual(metric?.uploadBytesPerSecond, 500)
        XCTAssertEqual(provider.sample(period: 1).value, metric)
    }

    func testNetworkPrimaryInterfaceFallsBackToIPv6() {
        let key = kSCDynamicStorePropNetPrimaryInterface as String

        XCTAssertEqual(
            NetworkProvider.primaryInterface(
                ipv4: nil,
                ipv6: [key: "en6"]
            ),
            "en6"
        )
        XCTAssertEqual(
            NetworkProvider.primaryInterface(
                ipv4: [key: "en0"],
                ipv6: [key: "en6"]
            ),
            "en0"
        )
    }

    func testNetworkRouteMessagePreservesCountersBeyondUInt32() {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        header.ifm_version = UInt8(RTM_VERSION)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_index = 7
        header.ifm_data.ifi_ibytes = UInt64(UInt32.max) + 2_000
        header.ifm_data.ifi_obytes = UInt64(UInt32.max) + 3_000
        let bytes = withUnsafeBytes(of: &header) { Array($0) }

        let counters = NetworkProvider.counters(
            in: bytes,
            byteCount: bytes.count,
            interfaceIndex: 7,
            interfaceName: "en0",
            uptime: 20
        )

        XCTAssertEqual(counters?.receivedBytes, UInt64(UInt32.max) + 2_000)
        XCTAssertEqual(counters?.sentBytes, UInt64(UInt32.max) + 3_000)
        let rate = counters.flatMap {
            NetworkProvider.calculate(
                previous: NetworkCounters(
                    interfaceName: "en0",
                    receivedBytes: UInt64(UInt32.max) + 1_000,
                    sentBytes: UInt64(UInt32.max) + 2_500,
                    uptime: 19
                ),
                current: $0
            )
        }
        XCTAssertEqual(rate?.downloadBytesPerSecond, 1_000)
        XCTAssertEqual(rate?.uploadBytesPerSecond, 500)
    }

    func testDiskProviderRejectsInconsistentCapacity() {
        let provider = DiskCapacityProvider {
            .success(
                DiskCapacityMetric(
                    totalBytes: 100,
                    freeBytes: 101,
                    availableBytes: 80
                )
            )
        }

        guard case .unavailable(.outOfRange) = provider.sample(period: 60) else {
            return XCTFail("Invalid filesystem capacity must be unavailable")
        }
    }

    func testDiskProviderTargetsStartupVolumeRoot() {
        XCTAssertEqual(DiskCapacityProvider.startupVolumeURL.path, "/")
    }

    func testHeatDiagnosisExplainsSustainedCPUWithoutScanningProcesses() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 90), stamp)
        snapshot.cpuHistorySummary = MetricHistorySummary(
            average: 75,
            peak: 95
        )

        let diagnosis = HeatDiagnosisAnalyzer.evaluate(snapshot)

        XCTAssertEqual(diagnosis.severity, .elevated)
        XCTAssertTrue(diagnosis.evidence.contains(.sustainedCPU))
        XCTAssertTrue(
            diagnosis.recommendations.contains(.inspectActivityMonitor)
        )
    }

    func testHotBatteryProducesUrgentCoolingRecommendations() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.batteryTemperature = .available(46, stamp)

        let diagnosis = HeatDiagnosisAnalyzer.evaluate(snapshot)

        XCTAssertEqual(diagnosis.severity, .urgent)
        XCTAssertTrue(diagnosis.evidence.contains(.hotBattery))
        XCTAssertTrue(diagnosis.recommendations.contains(.pauseCharging))
        XCTAssertTrue(diagnosis.recommendations.contains(.coolAndSeekService))
    }

    func testCriticalThermalStatePrioritizesStopAndCoolRecommendation() {
        var snapshot = SystemSnapshot.initial()
        snapshot.thermalLevel = .critical

        let diagnosis = HeatDiagnosisAnalyzer.evaluate(snapshot)

        XCTAssertEqual(diagnosis.severity, .urgent)
        XCTAssertEqual(diagnosis.recommendations.first, .coolAndSeekService)
    }

    func testMenuBarUsesConfiguredOrderSeparatorAndPrecision() {
        let stamp = SampleStamp(wallTime: Date(), uptime: 10)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 23.4), stamp)
        snapshot.disk = .available(
            DiskCapacityMetric(
                totalBytes: 100,
                freeBytes: 40,
                availableBytes: 35
            ),
            stamp
        )
        let preferences = PreferencesSnapshot(
            display: DisplaySettings(
                statusDisplayMode: .compact,
                compactMetrics: [.cpu, .disk],
                metricOrder: [.disk, .cpu, .memory, .battery, .network],
                statusSeparator: .bar,
                statusDecimalPlaces: 1,
                language: .english
            )
        )

        XCTAssertEqual(
            StatusItemController.presentation(
                preferences: preferences,
                snapshot: snapshot
            ).title,
            "Free 35.0% | CPU 23.4%"
        )
    }
}
