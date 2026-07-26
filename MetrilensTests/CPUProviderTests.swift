import XCTest
@testable import Metrilens

final class CPUProviderTests: XCTestCase {
    func testUtilizationUsesTickDeltas() throws {
        let previous = CPUTicks(user: 100, system: 50, nice: 10, idle: 840)
        let current = CPUTicks(user: 120, system: 60, nice: 10, idle: 910)
        let utilization = try XCTUnwrap(
            CPUProvider.utilization(previous: previous, current: current)
        )
        XCTAssertEqual(
            utilization,
            30,
            accuracy: 0.0001
        )
    }

    func testCounterRollbackIsRejected() {
        let previous = CPUTicks(user: 100, system: 50, nice: 10, idle: 840)
        let current = CPUTicks(user: 99, system: 60, nice: 10, idle: 900)
        XCTAssertNil(CPUProvider.utilization(previous: previous, current: current))
    }

    func testZeroDeltaIsRejected() {
        let ticks = CPUTicks(user: 100, system: 50, nice: 10, idle: 840)
        XCTAssertNil(CPUProvider.utilization(previous: ticks, current: ticks))
    }
}
