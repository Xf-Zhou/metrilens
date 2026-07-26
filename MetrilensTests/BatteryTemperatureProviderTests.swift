import XCTest
@testable import Metrilens

final class BatteryTemperatureProviderTests: XCTestCase {
    func testCurrentMachineBatteryReadingWhenPresent() throws {
        let provider = BatteryTemperatureProvider()
        switch provider.sampleCurrent(period: 60) {
        case let .available(value, _):
            XCTAssertTrue((-20...100).contains(value))
        case .unsupported(.noHardware):
            throw XCTSkip("This Mac has no AppleSmartBattery")
        case let .unsupported(error), let .unavailable(error):
            XCTFail("Current machine battery temperature failed: \(error)")
        case .stale:
            XCTFail("First hardware sample cannot be stale")
        }

        switch provider.sampleMaximum() {
        case let .available(value, _):
            XCTAssertTrue((0...100).contains(value))
        case .unsupported(.noHardware):
            throw XCTSkip("This Mac has no AppleSmartBattery")
        case let .unsupported(error), let .unavailable(error):
            XCTFail("Current machine maximum battery temperature failed: \(error)")
        case .stale:
            XCTFail("First hardware sample cannot be stale")
        }
    }

    func testCurrentTemperatureDecoder() {
        assertSuccess(
            BatteryTemperatureProvider.decodeCurrentTemperature(NSNumber(value: 3_091)),
            equals: 35.95
        )
        assertSuccess(
            BatteryTemperatureProvider.decodeCurrentTemperature(NSNumber(value: 2_532)),
            equals: -19.95
        )
        assertSuccess(
            BatteryTemperatureProvider.decodeCurrentTemperature(NSNumber(value: 3_731)),
            equals: 99.95
        )
    }

    func testCurrentTemperatureRejectsUnknownEncodingAndRange() {
        assertFailure(BatteryTemperatureProvider.decodeCurrentTemperature("3091"), .unsupportedEncoding)
        assertFailure(BatteryTemperatureProvider.decodeCurrentTemperature(NSNumber(value: 3_732)), .outOfRange)
        assertFailure(BatteryTemperatureProvider.decodeCurrentTemperature(NSNumber(value: 40)), .outOfRange)
        assertFailure(BatteryTemperatureProvider.decodeCurrentTemperature(nil), .unsupportedEncoding)
    }

    func testConclusiveUnsupportedCapabilitiesDisableRoutineSampling() {
        let noBattery = BatteryTemperatureProvider(propertiesReader: { .failure(.noHardware) })
        guard case .unsupported(.noHardware) = noBattery.sampleCurrent(period: 60) else {
            return XCTFail("Expected no hardware")
        }
        XCTAssertFalse(noBattery.shouldScheduleRoutineCurrentSample)

        let missingField = BatteryTemperatureProvider(propertiesReader: {
            .success(["BatteryData": [:]])
        })
        guard case .unsupported(.fieldMissing) = missingField.sampleCurrent(period: 60) else {
            return XCTFail("Expected field missing")
        }
        XCTAssertFalse(missingField.shouldScheduleRoutineCurrentSample)

        let unknownEncoding = BatteryTemperatureProvider(propertiesReader: {
            .success(["Temperature": "3091"])
        })
        guard case .unsupported(.unsupportedEncoding) = unknownEncoding.sampleCurrent(period: 60) else {
            return XCTFail("Expected unsupported encoding")
        }
        XCTAssertFalse(unknownEncoding.shouldScheduleRoutineCurrentSample)

        let transientOutOfRange = BatteryTemperatureProvider(propertiesReader: {
            .success(["Temperature": NSNumber(value: 3_732)])
        })
        guard case .unavailable(.outOfRange) = transientOutOfRange.sampleCurrent(period: 60) else {
            return XCTFail("Expected transient out-of-range failure")
        }
        XCTAssertTrue(transientOutOfRange.shouldScheduleRoutineCurrentSample)
    }

    func testMaximumTemperatureUsesIndependentCelsiusDecoder() {
        assertSuccess(
            BatteryTemperatureProvider.decodeMaximumTemperature(NSNumber(value: 40)),
            equals: 40
        )
        assertFailure(
            BatteryTemperatureProvider.decodeMaximumTemperature(NSNumber(value: 3_091)),
            .outOfRange
        )
    }

    func testMaximumUnknownEncodingClearsPreviouslyAvailableValue() {
        var reads = 0
        let provider = BatteryTemperatureProvider(propertiesReader: {
            reads += 1
            let maximum: Any = reads == 1 ? NSNumber(value: 40) : "40"
            return .success([
                "BatteryData": [
                    "LifetimeData": ["MaximumTemperature": maximum]
                ]
            ])
        })

        assertAvailable(provider.sampleMaximum(), equals: 40)
        guard case .unsupported(.unsupportedEncoding) = provider.sampleMaximum() else {
            return XCTFail("Unknown maximum encoding must clear the prior value")
        }
        XCTAssertNil(provider.maximumTemperature.value)
    }

    func testMaximumNoHardwareAlsoInvalidatesCurrentTemperatureSession() {
        var hasHardware = true
        let provider = BatteryTemperatureProvider(propertiesReader: {
            guard hasHardware else { return .failure(.noHardware) }
            return .success([
                "Temperature": NSNumber(value: 3_081),
                "BatteryData": [
                    "LifetimeData": ["MaximumTemperature": NSNumber(value: 40)]
                ]
            ])
        })
        assertAvailable(provider.sampleCurrent(period: 10), equals: 34.95)
        hasHardware = false

        guard case .unsupported(.noHardware) = provider.sampleMaximum() else {
            return XCTFail("Expected missing hardware")
        }
        guard case .unsupported(.noHardware) = provider.currentTemperature else {
            return XCTFail("The old current-temperature session must be invalidated")
        }
    }

    func testJumpRequiresConfirmation() {
        let provider = BatteryTemperatureProvider()
        assertAvailable(provider.acceptDecoded(35, stamp: stamp(0), period: 10), equals: 35)
        assertStale(provider.acceptDecoded(60, stamp: stamp(1), period: 10), equals: 35)
        assertStale(provider.currentTemperature, equals: 35)
        assertAvailable(provider.acceptDecoded(60, stamp: stamp(2), period: 10), equals: 60)
    }

    func testMaximumReadCannotRestoreCandidateStateToAvailable() {
        let provider = BatteryTemperatureProvider(propertiesReader: {
            .success([
                "BatteryData": [
                    "LifetimeData": ["MaximumTemperature": NSNumber(value: 40)]
                ]
            ])
        })
        assertAvailable(provider.acceptDecoded(35, stamp: stamp(0), period: 10), equals: 35)
        assertStale(provider.acceptDecoded(60, stamp: stamp(1), period: 10), equals: 35)
        assertAvailable(provider.sampleMaximum(), equals: 40)
        assertStale(provider.currentTemperature, equals: 35)
    }

    func testNewCandidateReplacesUnconfirmedJump() {
        let provider = BatteryTemperatureProvider()
        assertAvailable(provider.acceptDecoded(35, stamp: stamp(0), period: 10), equals: 35)
        assertStale(provider.acceptDecoded(60, stamp: stamp(1), period: 10), equals: 35)
        assertStale(provider.acceptDecoded(45, stamp: stamp(2), period: 10), equals: 35)
        assertAvailable(provider.acceptDecoded(45, stamp: stamp(3), period: 10), equals: 45)
    }

    func testPauseAndCapabilityResetClearCandidate() {
        let provider = BatteryTemperatureProvider()
        assertAvailable(provider.acceptDecoded(35, stamp: stamp(0), period: 10), equals: 35)
        assertStale(provider.acceptDecoded(60, stamp: stamp(1), period: 10), equals: 35)
        provider.pause(nowUptime: 100)
        assertStale(provider.acceptDecoded(60, stamp: stamp(2), period: 10), equals: 35)
        provider.resetCapabilities()
        assertAvailable(provider.acceptDecoded(60, stamp: stamp(3), period: 10), equals: 60)
    }

    func testExpiredCandidateRequiresFreshConfirmationAgainstLastAcceptedValue() {
        let provider = BatteryTemperatureProvider()
        assertAvailable(provider.acceptDecoded(35, stamp: stamp(0), period: 10), equals: 35)
        assertStale(provider.acceptDecoded(60, stamp: stamp(1), period: 10), equals: 35)
        assertStale(provider.acceptDecoded(60, stamp: stamp(121), period: 10), equals: 35)
        assertAvailable(provider.acceptDecoded(60, stamp: stamp(122), period: 10), equals: 60)
    }

    func testUnsupportedCapabilityCannotResurrectDiscardedAcceptedValue() {
        var properties: [String: Any] = ["Temperature": NSNumber(value: 3_081)]
        let provider = BatteryTemperatureProvider(propertiesReader: { .success(properties) })
        assertAvailable(provider.sampleCurrent(period: 10), equals: 34.95)

        properties = [:]
        guard case .unsupported(.fieldMissing) = provider.sampleCurrent(period: 10) else {
            return XCTFail("Expected terminal capability state")
        }
        provider.resetCapabilities()
        assertAvailable(provider.acceptDecoded(60, stamp: stamp(10), period: 10), equals: 60)
    }

    func testFailureThresholdCannotResurrectDiscardedAcceptedValue() {
        var properties: [String: Any] = ["Temperature": NSNumber(value: 3_081)]
        let provider = BatteryTemperatureProvider(propertiesReader: { .success(properties) })
        assertAvailable(provider.sampleCurrent(period: 10), equals: 34.95)

        properties = ["Temperature": NSNumber(value: 3_732)]
        assertStale(provider.sampleCurrent(period: 10), equals: 34.95)
        guard case .unavailable(.outOfRange) = provider.sampleCurrent(period: 10) else {
            return XCTFail("Expected failure threshold to discard the value")
        }
        assertAvailable(provider.acceptDecoded(60, stamp: stamp(10), period: 10), equals: 60)
    }

    func testCurrentNoHardwareClearsPreviouslyAvailableMaximum() {
        var hasHardware = true
        let provider = BatteryTemperatureProvider(propertiesReader: {
            guard hasHardware else { return .failure(.noHardware) }
            return .success([
                "Temperature": NSNumber(value: 3_081),
                "BatteryData": [
                    "LifetimeData": ["MaximumTemperature": NSNumber(value: 40)]
                ]
            ])
        })
        assertAvailable(provider.sampleCurrent(period: 10), equals: 34.95)
        assertAvailable(provider.sampleMaximum(), equals: 40)

        hasHardware = false
        guard case .unsupported(.noHardware) = provider.sampleCurrent(period: 10),
              case .unsupported(.noHardware) = provider.maximumTemperature else {
            return XCTFail("Battery removal must invalidate both temperatures")
        }
        XCTAssertNil(provider.maximumTemperature.value)
    }

    private func stamp(_ uptime: TimeInterval) -> SampleStamp {
        SampleStamp(wallTime: Date(timeIntervalSince1970: uptime), uptime: uptime)
    }

    private func assertSuccess(
        _ result: Result<Double, MetricFailure>,
        equals value: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .success(actual) = result else {
            return XCTFail("Expected success", file: file, line: line)
        }
        XCTAssertEqual(actual, value, accuracy: 0.001, file: file, line: line)
    }

    private func assertFailure(
        _ result: Result<Double, MetricFailure>,
        _ failure: MetricFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .failure(actual) = result else {
            return XCTFail("Expected failure", file: file, line: line)
        }
        XCTAssertEqual(actual, failure, file: file, line: line)
    }

    private func assertAvailable(
        _ state: MetricState<Double>,
        equals value: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .available(actual, _) = state else {
            return XCTFail("Expected available", file: file, line: line)
        }
        XCTAssertEqual(actual, value, accuracy: 0.001, file: file, line: line)
    }

    private func assertStale(
        _ state: MetricState<Double>,
        equals value: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .stale(actual, _) = state else {
            return XCTFail("Expected stale", file: file, line: line)
        }
        XCTAssertEqual(actual, value, accuracy: 0.001, file: file, line: line)
    }
}
