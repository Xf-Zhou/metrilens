import XCTest
import UserNotifications
@testable import Metrilens

final class MetricAlertTests: XCTestCase {
    func testSustainedCPUThresholdRequiresFreshValueAndHonorsCooldown() {
        var evaluator = MetricAlertEvaluator(cooldown: 600)
        let preferences = alertPreferences()
        let stamp = SampleStamp(wallTime: Date(), uptime: 0)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 95), stamp)

        XCTAssertTrue(
            evaluator.evaluate(
                snapshot: snapshot,
                preferences: preferences,
                nowUptime: 100
            ).isEmpty
        )
        XCTAssertEqual(
            evaluator.evaluate(
                snapshot: snapshot,
                preferences: preferences,
                nowUptime: 130
            ),
            [MetricAlertEvent(kind: .cpu, value: 95, thermalLevel: nil)]
        )
        XCTAssertTrue(
            evaluator.evaluate(
                snapshot: snapshot,
                preferences: preferences,
                nowUptime: 500
            ).isEmpty
        )
        snapshot.cpu = .stale(CPUMetric(percent: 95), stamp)
        XCTAssertTrue(
            evaluator.evaluate(
                snapshot: snapshot,
                preferences: preferences,
                nowUptime: 730
            ).isEmpty
        )
    }

    func testDroppingBelowThresholdRestartsSustainWindow() {
        var evaluator = MetricAlertEvaluator(cooldown: 600)
        let preferences = alertPreferences()
        let stamp = SampleStamp(wallTime: Date(), uptime: 0)
        var snapshot = SystemSnapshot.initial()
        snapshot.memory = memoryState(percent: 95, stamp: stamp)
        _ = evaluator.evaluate(
            snapshot: snapshot,
            preferences: preferences,
            nowUptime: 0
        )
        snapshot.memory = memoryState(percent: 50, stamp: stamp)
        _ = evaluator.evaluate(
            snapshot: snapshot,
            preferences: preferences,
            nowUptime: 20
        )
        snapshot.memory = memoryState(percent: 95, stamp: stamp)

        XCTAssertTrue(
            evaluator.evaluate(
                snapshot: snapshot,
                preferences: preferences,
                nowUptime: 40
            ).isEmpty
        )
        XCTAssertEqual(
            evaluator.evaluate(
                snapshot: snapshot,
                preferences: preferences,
                nowUptime: 70
            ).map(\.kind),
            [.memory]
        )
    }

    func testThermalWarningIsImmediateAndLocalized() {
        var evaluator = MetricAlertEvaluator(cooldown: 600)
        let preferences = alertPreferences()
        var snapshot = SystemSnapshot.initial()
        snapshot.thermalLevel = .critical

        let events = evaluator.evaluate(
            snapshot: snapshot,
            preferences: preferences,
            nowUptime: 10
        )

        XCTAssertEqual(events.map(\.kind), [.thermal])
        let content = MetricAlertController.content(
            for: events[0],
            language: .english
        )
        XCTAssertEqual(content.title, "System Thermal Warning")
        XCTAssertTrue(content.body.contains("Critical"))
    }

    func testDisabledAlertsResetPendingThreshold() {
        var evaluator = MetricAlertEvaluator(cooldown: 600)
        let enabled = alertPreferences()
        let disabled = PreferencesSnapshot(
            primaryMetric: .cpu,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true,
            alertsEnabled: false
        )
        let stamp = SampleStamp(wallTime: Date(), uptime: 0)
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 95), stamp)
        _ = evaluator.evaluate(
            snapshot: snapshot,
            preferences: enabled,
            nowUptime: 0
        )
        _ = evaluator.evaluate(
            snapshot: snapshot,
            preferences: disabled,
            nowUptime: 20
        )

        XCTAssertTrue(
            evaluator.evaluate(
                snapshot: snapshot,
                preferences: enabled,
                nowUptime: 31
            ).isEmpty
        )
    }

    func testChangingCPUThresholdDoesNotClearThermalCooldown() {
        var uptime: TimeInterval = 0
        let delivery = FakeNotificationDelivery()
        let authorizationReady = expectation(description: "authorization applied")
        let controller = MetricAlertController(
            preferences: alertPreferences(),
            delivery: delivery,
            uptimeProvider: { uptime }
        )
        DispatchQueue.main.async {
            authorizationReady.fulfill()
        }
        wait(for: [authorizationReady], timeout: 1)

        var snapshot = SystemSnapshot.initial()
        snapshot.thermalLevel = .critical
        controller.handle(snapshot: snapshot)
        XCTAssertEqual(delivery.deliveredKinds, ["metrilens.alert.thermal"])

        controller.setPreferences(
            PreferencesSnapshot(
                primaryMetric: .cpu,
                refreshInterval: 1,
                launchAtLogin: false,
                showsSparkline: true,
                alertsEnabled: true,
                cpuAlertThreshold: 95,
                memoryAlertThreshold: 90,
                alertSustainDuration: 30
            )
        )
        uptime = 1
        controller.handle(snapshot: snapshot)

        XCTAssertEqual(delivery.deliveredKinds, ["metrilens.alert.thermal"])
        XCTAssertEqual(delivery.authorizationRequestCount, 1)
    }

    func testForegroundNotificationsRequestBannerAndSound() {
        let options = UserNotificationDelivery.foregroundPresentationOptions

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
    }

    private func alertPreferences() -> PreferencesSnapshot {
        PreferencesSnapshot(
            primaryMetric: .cpu,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true,
            alertsEnabled: true,
            cpuAlertThreshold: 90,
            memoryAlertThreshold: 90,
            alertSustainDuration: 30
        )
    }

    private func memoryState(
        percent: UInt64,
        stamp: SampleStamp
    ) -> MetricState<MemoryMetric> {
        .available(
            MemoryMetric(
                usedBytes: percent,
                totalBytes: 100,
                availableBytes: 100 - percent,
                purgeableBytes: 0
            ),
            stamp
        )
    }
}

private final class FakeNotificationDelivery: LocalNotificationDelivering {
    var authorizationRequestCount = 0
    var deliveredKinds: [String] = []

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        authorizationRequestCount += 1
        completion(true)
    }

    func deliver(identifier: String, title: String, body: String) {
        deliveredKinds.append(
            identifier.components(separatedBy: ".").dropLast().joined(separator: ".")
        )
    }
}
