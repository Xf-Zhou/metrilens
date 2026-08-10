import AppKit
import XCTest
@testable import Metrilens

final class DocumentationScreenshotTests: XCTestCase {
    func testPopoverDocumentationScreenshotRenders() throws {
        let stamp = SampleStamp(
            wallTime: Date(timeIntervalSince1970: 1_785_000_000),
            uptime: 1_000
        )
        var snapshot = SystemSnapshot.initial()
        snapshot.cpu = .available(CPUMetric(percent: 18.4), stamp)
        snapshot.memory = .available(
            MemoryMetric(
                usedBytes: 6_872_000_000,
                totalBytes: 16_000_000_000,
                availableBytes: 9_128_000_000,
                purgeableBytes: 480_000_000
            ),
            stamp
        )
        snapshot.battery = .available(
            BatteryMetric(
                levelPercent: 82,
                powerState: .externalPower,
                cycleCount: 168,
                health: .good,
                timeRemainingMinutes: nil
            ),
            stamp
        )
        snapshot.batteryTemperature = .available(33.8, stamp)
        snapshot.batterySessionMaximumTemperature = .available(36.2, stamp)
        snapshot.batteryMaximumTemperature = .available(41.5, stamp)
        snapshot.network = .available(
            NetworkMetric(
                downloadBytesPerSecond: 2_480_000,
                uploadBytesPerSecond: 184_000,
                interfaceName: "en0"
            ),
            stamp
        )
        snapshot.disk = .available(
            DiskCapacityMetric(
                totalBytes: 1_000_000_000_000,
                freeBytes: 438_000_000_000,
                availableBytes: 412_000_000_000
            ),
            stamp
        )
        snapshot.thermalLevel = .nominal
        snapshot.cpuHistory = history(base: 16, amplitude: 8)
        snapshot.cpuHistoryCollecting = false
        snapshot.cpuHistorySummary = MetricHistorySummary(average: 18.1, peak: 31.6)
        snapshot.memoryHistory = history(base: 42, amplitude: 3)
        snapshot.memoryHistoryCollecting = false
        snapshot.memoryHistorySummary = MetricHistorySummary(average: 42.4, peak: 46.1)

        let controller = PopoverController(
            preferences: PreferencesSnapshot(
                display: DisplaySettings(language: .simplifiedChinese),
                sampling: SamplingSettings(showsSparkline: true)
            )
        )
        controller.update(snapshot: snapshot)
        let view = try XCTUnwrap(controller.popover.contentViewController?.view)
        view.appearance = NSAppearance(named: .aqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.cornerRadius = 10
        view.frame = NSRect(origin: .zero, size: controller.popover.contentSize)
        view.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds)
        )
        view.cacheDisplay(in: view.bounds, to: representation)
        let data = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        XCTAssertGreaterThan(data.count, 20_000)

        try data.write(
            to: URL(fileURLWithPath: "/tmp/metrilens-doc-popover.png"),
            options: .atomic
        )
    }

    private func history(base: Double, amplitude: Double) -> [MetricHistoryPoint] {
        (0..<60).map { index in
            MetricHistoryPoint(
                uptime: Double(index),
                percent: base + sin(Double(index) / 5) * amplitude
            )
        }
    }
}
