import CoreFoundation
import Foundation
import IOKit

struct BatteryCapabilities: Equatable {
    var hardwarePresent = false
    var currentFieldPresent = false
    var currentDecoderSupported = false
    var maximumFieldPresent = false
    var maximumDecoderSupported = false
}

private struct TemperatureCandidate {
    let value: Double
    let firstSeenUptime: TimeInterval
    let expiresAtUptime: TimeInterval
}

protocol BatteryTemperatureProviding: AnyObject {
    var currentTemperature: MetricState<Double> { get }
    var maximumTemperature: MetricState<Double> { get }
    var shouldScheduleRoutineCurrentSample: Bool { get }
    func sampleCurrent(period: TimeInterval) -> MetricState<Double>
    func sampleMaximum() -> MetricState<Double>
    func pause()
    func resetCapabilities()
    func expireMaximumIfNeeded(nowUptime: TimeInterval)
}

final class BatteryTemperatureProvider: BatteryTemperatureProviding {
    typealias PropertiesReader = () -> Result<[String: Any], MetricFailure>

    private let currentState = MetricStateMachine<Double>()
    private let maximumState = MetricStateMachine<Double>()
    private let propertiesReader: PropertiesReader
    private var candidate: TemperatureCandidate?
    private var lastAccepted: (value: Double, stamp: SampleStamp)?
    private var hasProbedCurrentCapability = false

    private(set) var capabilities = BatteryCapabilities()

    var currentTemperature: MetricState<Double> { currentState.state }
    var maximumTemperature: MetricState<Double> { maximumState.state }
    var shouldScheduleRoutineCurrentSample: Bool {
        !hasProbedCurrentCapability
            || (capabilities.hardwarePresent
                && capabilities.currentFieldPresent
                && capabilities.currentDecoderSupported)
    }

    init(propertiesReader: @escaping PropertiesReader = BatteryTemperatureProvider.readSystemProperties) {
        self.propertiesReader = propertiesReader
    }

    func sampleCurrent(period: TimeInterval) -> MetricState<Double> {
        let now = SampleStamp.now()
        switch propertiesReader() {
        case let .success(properties):
            hasProbedCurrentCapability = true
            capabilities.hardwarePresent = true
            guard properties["Temperature"] != nil else {
                capabilities.currentFieldPresent = false
                capabilities.currentDecoderSupported = false
                candidate = nil
                lastAccepted = nil
                return currentState.recordUnsupported(.fieldMissing)
            }
            capabilities.currentFieldPresent = true
            switch Self.decodeCurrentTemperature(properties["Temperature"]) {
            case let .success(value):
                capabilities.currentDecoderSupported = true
                return acceptDecoded(value, stamp: now, period: period)
            case let .failure(error):
                candidate = nil
                if error == .unsupportedEncoding {
                    capabilities.currentDecoderSupported = false
                    lastAccepted = nil
                    return currentState.recordUnsupported(error)
                }
                capabilities.currentDecoderSupported = true
                return recordCurrentFailure(
                    error,
                    period: period
                )
            }
        case let .failure(error):
            candidate = nil
            if error == .noHardware {
                hasProbedCurrentCapability = true
                capabilities = BatteryCapabilities()
                lastAccepted = nil
                _ = maximumState.recordUnsupported(.noHardware)
                return currentState.recordUnsupported(.noHardware)
            }
            return recordCurrentFailure(error, period: period)
        }
    }

    func sampleMaximum() -> MetricState<Double> {
        switch propertiesReader() {
        case let .success(properties):
            capabilities.hardwarePresent = true
            guard let batteryData = Self.dictionary(properties["BatteryData"]),
                  let lifetimeData = Self.dictionary(batteryData["LifetimeData"]),
                  let raw = lifetimeData["MaximumTemperature"] else {
                capabilities.maximumFieldPresent = false
                capabilities.maximumDecoderSupported = false
                return maximumState.recordUnsupported(.fieldMissing)
            }
            capabilities.maximumFieldPresent = true
            switch Self.decodeMaximumTemperature(raw) {
            case let .success(value):
                capabilities.maximumDecoderSupported = true
                return maximumState.recordSuccess(value)
            case let .failure(error):
                if error == .unsupportedEncoding {
                    capabilities.maximumDecoderSupported = false
                    return maximumState.recordUnsupported(error)
                }
                capabilities.maximumDecoderSupported = true
                return maximumState.recordFailure(error, failureLimit: 2, ttl: 3_600)
            }
        case let .failure(error):
            if error == .noHardware {
                capabilities = BatteryCapabilities()
                hasProbedCurrentCapability = true
                candidate = nil
                lastAccepted = nil
                _ = currentState.recordUnsupported(.noHardware)
                return maximumState.recordUnsupported(.noHardware)
            }
            return maximumState.recordFailure(error, failureLimit: 2, ttl: 3_600)
        }
    }

    func pause() {
        candidate = nil
    }

    func resetCapabilities() {
        candidate = nil
        lastAccepted = nil
        hasProbedCurrentCapability = false
        capabilities = BatteryCapabilities()
        currentState.reset()
    }

    func expireMaximumIfNeeded(nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        _ = maximumState.expireFailedValueIfNeeded(nowUptime: nowUptime, ttl: 3_600)
    }

    static func decodeCurrentTemperature(_ rawValue: Any?) -> Result<Double, MetricFailure> {
        guard let rawValue, let raw = exactInteger(rawValue) else {
            return .failure(.unsupportedEncoding)
        }
        guard (2_532...3_731).contains(raw) else {
            return .failure(.outOfRange)
        }
        let celsius = Double(raw) / 10 - 273.15
        guard (-20...100).contains(celsius) else {
            return .failure(.outOfRange)
        }
        return .success(celsius)
    }

    static func decodeMaximumTemperature(_ rawValue: Any?) -> Result<Double, MetricFailure> {
        guard let rawValue, let raw = exactInteger(rawValue) else {
            return .failure(.unsupportedEncoding)
        }
        guard (0...100).contains(raw) else {
            return .failure(.outOfRange)
        }
        return .success(Double(raw))
    }

    func acceptDecoded(
        _ value: Double,
        stamp: SampleStamp,
        period: TimeInterval
    ) -> MetricState<Double> {
        if let existing = candidate {
            if stamp.uptime >= existing.expiresAtUptime {
                candidate = nil
                return evaluateAgainstLastAccepted(
                    value,
                    stamp: stamp,
                    period: period,
                    requireJumpConfirmation: true
                )
            } else if abs(value - existing.value) <= 2 {
                candidate = nil
                lastAccepted = (value, stamp)
                return currentState.recordSuccess(value, stamp: stamp)
            } else {
                candidate = makeCandidate(value: value, now: stamp.uptime, period: period)
                return candidateOutput()
            }
        }

        return evaluateAgainstLastAccepted(
            value,
            stamp: stamp,
            period: period,
            requireJumpConfirmation: false
        )
    }

    private func evaluateAgainstLastAccepted(
        _ value: Double,
        stamp: SampleStamp,
        period: TimeInterval,
        requireJumpConfirmation: Bool
    ) -> MetricState<Double> {
        if let lastAccepted,
           (requireJumpConfirmation || stamp.uptime - lastAccepted.stamp.uptime <= 120),
           abs(value - lastAccepted.value) > 15 {
            candidate = makeCandidate(value: value, now: stamp.uptime, period: period)
            return candidateOutput()
        }

        candidate = nil
        lastAccepted = (value, stamp)
        return currentState.recordSuccess(value, stamp: stamp)
    }

    private func makeCandidate(
        value: Double,
        now: TimeInterval,
        period: TimeInterval
    ) -> TemperatureCandidate {
        TemperatureCandidate(
            value: value,
            firstSeenUptime: now,
            expiresAtUptime: now + max(120, period * 2 + 5)
        )
    }

    private func candidateOutput() -> MetricState<Double> {
        if let lastAccepted {
            return currentState.presentProvisionalStale(
                lastAccepted.value,
                stamp: lastAccepted.stamp
            )
        }
        return currentState.presentProvisionalUnavailable(.outlierJump)
    }

    private func recordCurrentFailure(
        _ error: MetricFailure,
        period: TimeInterval
    ) -> MetricState<Double> {
        let result = currentState.recordFailure(
            error,
            failureLimit: 2,
            ttl: max(60, period * 2)
        )
        if case .unavailable = result {
            lastAccepted = nil
        }
        return result
    }

    static func readSystemProperties() -> Result<[String: Any], MetricFailure> {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return .failure(.unsupportedEncoding)
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            return .failure(.noHardware)
        }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS, let unmanagedProperties else {
            return .failure(.iokitFailure(result))
        }
        let dictionary = unmanagedProperties.takeRetainedValue() as NSDictionary
        guard let properties = dictionary as? [String: Any] else {
            return .failure(.unsupportedEncoding)
        }
        return .success(properties)
    }

    private static func exactInteger(_ value: Any) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID() else {
            return nil
        }
        var integer: Int64 = 0
        guard CFNumberGetValue(number, .sInt64Type, &integer) else {
            return nil
        }
        let decimal = number.doubleValue
        guard decimal.isFinite, decimal == Double(integer) else {
            return nil
        }
        return integer
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let dictionary = value as? NSDictionary {
            return dictionary as? [String: Any]
        }
        return nil
    }
}
