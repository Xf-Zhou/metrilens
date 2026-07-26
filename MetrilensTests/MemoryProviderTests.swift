import XCTest
@testable import Metrilens

final class MemoryProviderTests: XCTestCase {
    func testDocumentedMemoryFormula() throws {
        let counters = MemoryCounters(
            internalPages: 40,
            wiredPages: 20,
            compressorPages: 10,
            purgeablePages: 5,
            pageSize: 4_096,
            totalBytes: 100 * 4_096
        )
        let metric = try XCTUnwrap(tryValue(MemoryProvider.calculate(counters)))
        XCTAssertEqual(metric.usedBytes, 70 * 4_096)
        XCTAssertEqual(metric.availableBytes, 30 * 4_096)
        XCTAssertEqual(metric.purgeableBytes, 5 * 4_096)
        XCTAssertEqual(metric.percent, 70, accuracy: 0.0001)
    }

    func testUsedBytesClampToPhysicalMemory() throws {
        let counters = MemoryCounters(
            internalPages: 80,
            wiredPages: 30,
            compressorPages: 10,
            purgeablePages: 5,
            pageSize: 4_096,
            totalBytes: 100 * 4_096
        )
        let metric = try XCTUnwrap(tryValue(MemoryProvider.calculate(counters)))
        XCTAssertEqual(metric.usedBytes, counters.totalBytes)
        XCTAssertEqual(metric.availableBytes, 0)
    }

    func testOverflowFails() {
        let counters = MemoryCounters(
            internalPages: .max,
            wiredPages: 1,
            compressorPages: 0,
            purgeablePages: 0,
            pageSize: 4_096,
            totalBytes: 100 * 4_096
        )
        guard case .failure(.counterOverflow) = MemoryProvider.calculate(counters) else {
            return XCTFail("Expected counterOverflow")
        }
    }

    func testRecordedRealMachineFixture() throws {
        let counters = MemoryCounters(
            internalPages: 247_172,
            wiredPages: 272_556,
            compressorPages: 345_157,
            purgeablePages: 3_264,
            pageSize: 16_384,
            totalBytes: 16 * 1_024 * 1_024 * 1_024
        )
        let metric = try XCTUnwrap(tryValue(MemoryProvider.calculate(counters)))
        XCTAssertEqual(metric.usedBytes, 14_170_275_840)
        XCTAssertLessThan(metric.usedBytes, metric.totalBytes)
        XCTAssertEqual(metric.percent, 82.48, accuracy: 0.01)
    }

    private func tryValue<T>(_ result: Result<T, MetricFailure>) -> T? {
        guard case let .success(value) = result else { return nil }
        return value
    }
}
