import XCTest
@testable import Metrilens

final class SamplingAndHistoryTests: XCTestCase {
    func testUIEventStormKeepsOneTimerAndCooldown() {
        let queue = DispatchQueue(label: "scheduler-test")
        let firstFire = expectation(description: "initial provider fire")
        firstFire.expectedFulfillmentCount = 2
        var fireCounts: [ProviderID: Int] = [:]
        var scheduler: ProviderDeadlineScheduler!
        scheduler = ProviderDeadlineScheduler(queue: queue) { providers in
            for provider in providers {
                fireCounts[provider, default: 0] += 1
                scheduler.complete(provider)
                firstFire.fulfill()
            }
        }

        queue.async {
            for _ in 0..<100 {
                scheduler.update(periods: [.cpu: 1, .battery: 10])
            }
        }
        wait(for: [firstFire], timeout: 1)

        queue.sync {
            for _ in 0..<100 {
                scheduler.update(periods: [.cpu: 1, .battery: 10])
            }
            let state = scheduler.debugState()
            XCTAssertEqual(state.activeTimerCount, 1)
            XCTAssertTrue(state.inFlightProviders.isEmpty)
            XCTAssertEqual(state.scheduledProviders, [.cpu, .battery])
            XCTAssertEqual(fireCounts[.cpu], 1)
            XCTAssertEqual(fireCounts[.battery], 1)
            scheduler.stop()
        }
    }

    func testUpdatesCannotRefireProviderWhileItsSampleIsInFlight() {
        let queue = DispatchQueue(label: "scheduler-inflight-test")
        let firstFire = expectation(description: "provider enters in-flight state")
        var fireCount = 0
        var scheduler: ProviderDeadlineScheduler!
        scheduler = ProviderDeadlineScheduler(queue: queue) { providers in
            XCTAssertEqual(providers, [.cpu])
            fireCount += 1
            firstFire.fulfill()
        }

        queue.async {
            scheduler.update(periods: [.cpu: 1])
        }
        wait(for: [firstFire], timeout: 1)
        queue.sync {
            for _ in 0..<100 {
                scheduler.update(periods: [.cpu: 1], force: [.cpu])
            }
            let state = scheduler.debugState()
            XCTAssertEqual(fireCount, 1)
            XCTAssertEqual(state.inFlightProviders, [.cpu])
            scheduler.complete(.cpu)
            scheduler.stop()
        }
    }

    func testCPUHistoryPrunesByTimeAndCapacity() {
        var buffer = CPUHistoryBuffer(window: 60, capacity: 3)
        XCTAssertTrue(buffer.isCollecting(now: 0))
        buffer.append(percent: 10, at: 0)
        buffer.append(percent: 20, at: 1)
        buffer.append(percent: 30, at: 2)
        buffer.append(percent: 40, at: 3)
        XCTAssertEqual(buffer.values(now: 3).map(\.percent), [20, 30, 40])
        XCTAssertEqual(buffer.values(now: 62).map(\.percent), [30, 40])
        XCTAssertFalse(buffer.isCollecting(now: 62))
        XCTAssertTrue(buffer.values(now: 64).isEmpty)
        buffer.clear()
        XCTAssertTrue(buffer.isCollecting(now: 64))
    }

    func testMetricHistorySummaryUsesOnlyCurrentWindow() {
        var buffer = MetricHistoryBuffer(window: 60, capacity: 10)
        buffer.append(percent: 10, at: 0)
        buffer.append(percent: 40, at: 30)
        buffer.append(percent: 70, at: 61)

        XCTAssertEqual(
            buffer.summary(now: 61),
            MetricHistorySummary(average: 55, peak: 70)
        )
    }

    func testSamplingPolicyForClosedPopover() {
        let cpu = PreferencesSnapshot(
            primaryMetric: .cpu,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true
        )
        XCTAssertEqual(
            SamplingPolicy.resolve(
                preferences: cpu,
                popoverVisible: false,
                lowPower: false,
                sleeping: false
            ),
            [.cpu: 1]
        )

        let battery = PreferencesSnapshot(
            primaryMetric: .battery,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true
        )
        XCTAssertEqual(
            SamplingPolicy.resolve(
                preferences: battery,
                popoverVisible: false,
                lowPower: false,
                sleeping: false
            ),
            [.battery: 30]
        )
    }

    func testSamplingPolicyForPopoverLowPowerAndSleep() {
        let preferences = PreferencesSnapshot(
            primaryMetric: .memory,
            refreshInterval: 1,
            launchAtLogin: false,
            showsSparkline: true
        )
        XCTAssertEqual(
            SamplingPolicy.resolve(
                preferences: preferences,
                popoverVisible: true,
                lowPower: false,
                sleeping: false
            ),
            [.cpu: 1, .memory: 1, .battery: 10]
        )
        XCTAssertEqual(
            SamplingPolicy.resolve(
                preferences: preferences,
                popoverVisible: true,
                lowPower: true,
                sleeping: false
            ),
            [.cpu: 5, .memory: 5, .battery: 120]
        )
        XCTAssertTrue(
            SamplingPolicy.resolve(
                preferences: preferences,
                popoverVisible: true,
                lowPower: false,
                sleeping: true
            ).isEmpty
        )
    }

    func testCompactModeSamplesEverySelectedMetric() {
        let preferences = PreferencesSnapshot(
            primaryMetric: .cpu,
            refreshInterval: 2,
            launchAtLogin: false,
            showsSparkline: true,
            statusDisplayMode: .compact,
            compactMetrics: [.memory, .battery]
        )

        XCTAssertEqual(
            SamplingPolicy.resolve(
                preferences: preferences,
                popoverVisible: false,
                lowPower: false,
                sleeping: false
            ),
            [.memory: 2, .battery: 30]
        )
    }

    func testAlertsKeepCPUAndMemorySamplingActiveWhenPopoverIsClosed() {
        let preferences = PreferencesSnapshot(
            primaryMetric: .battery,
            refreshInterval: 2,
            launchAtLogin: false,
            showsSparkline: true,
            alertsEnabled: true
        )

        XCTAssertEqual(
            SamplingPolicy.resolve(
                preferences: preferences,
                popoverVisible: false,
                lowPower: false,
                sleeping: false
            ),
            [.cpu: 2, .memory: 2, .battery: 30]
        )
    }
}
