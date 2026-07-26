import CoreFoundation
import Foundation
import IOKit.ps

protocol BatteryStatusProviding: AnyObject {
    var state: MetricState<BatteryMetric> { get }
    var lastSampleFailure: MetricFailure? { get }
    func sample(period: TimeInterval) -> MetricState<BatteryMetric>
    func pause(nowUptime: TimeInterval)
    func expireCachedValue(nowUptime: TimeInterval)
    func resetCapabilities()
}

final class BatteryStatusProvider: BatteryStatusProviding {
    typealias PropertiesReader = () -> Result<[String: Any], MetricFailure>

    private let stateMachine = MetricStateMachine<BatteryMetric>()
    private let propertiesReader: PropertiesReader
    private var cacheTTL: TimeInterval = 120

    var state: MetricState<BatteryMetric> { stateMachine.state }
    private(set) var lastSampleFailure: MetricFailure?

    init(
        propertiesReader: @escaping PropertiesReader =
            BatteryStatusProvider.readSystemProperties
    ) {
        self.propertiesReader = propertiesReader
    }

    func sample(period: TimeInterval) -> MetricState<BatteryMetric> {
        cacheTTL = max(120, period * 3)
        switch propertiesReader() {
        case let .success(properties):
            switch Self.decode(properties) {
            case let .success(metric):
                lastSampleFailure = nil
                return stateMachine.recordSuccess(metric)
            case let .failure(failure):
                lastSampleFailure = failure
                return stateMachine.recordFailure(
                    failure,
                    failureLimit: 2,
                    ttl: cacheTTL
                )
            }
        case let .failure(failure):
            lastSampleFailure = failure
            if failure == .noHardware {
                return stateMachine.recordUnsupported(failure)
            }
            return stateMachine.recordFailure(
                failure,
                failureLimit: 2,
                ttl: cacheTTL
            )
        }
    }

    func pause(nowUptime: TimeInterval) {
        _ = stateMachine.preserveFreshValueAsStale(
            nowUptime: nowUptime,
            ttl: cacheTTL
        )
    }

    func expireCachedValue(nowUptime: TimeInterval) {
        _ = stateMachine.expireFailedValueIfNeeded(
            nowUptime: nowUptime,
            ttl: cacheTTL
        )
    }

    func resetCapabilities() {
        stateMachine.reset()
        lastSampleFailure = nil
    }

    static func decode(
        _ properties: [String: Any]
    ) -> Result<BatteryMetric, MetricFailure> {
        guard let current = exactInteger(properties["CurrentCapacity"]),
              let maximum = exactInteger(properties["MaxCapacity"]) else {
            return .failure(.fieldMissing)
        }
        guard maximum > 0, current >= 0 else {
            return .failure(.outOfRange)
        }
        let (maximumAllowed, overflow) =
            maximum.multipliedReportingOverflow(by: 2)
        guard !overflow, current <= maximumAllowed else {
            return .failure(.outOfRange)
        }

        let charging = bool(properties["IsCharging"])
        let externalConnected = bool(properties["ExternalConnected"])
        let fullyCharged = bool(properties["FullyCharged"])
        let state: BatteryPowerState
        if charging == true {
            state = .charging
        } else if fullyCharged == true {
            state = .charged
        } else if externalConnected == true {
            state = .externalPower
        } else if externalConnected == false {
            state = .discharging
        } else {
            state = .unknown
        }

        let condition = string(properties["BatteryHealthCondition"])
            ?? string(properties["BatteryHealth"])
        let health: BatteryHealth
        switch condition?.lowercased() {
        case "good": health = .good
        case "fair": health = .fair
        case "poor": health = .poor
        case "check battery", "permanent failure", "service recommended":
            health = .serviceRecommended
        default:
            health = .unknown
        }

        let cycle = exactInteger(properties["CycleCount"]).flatMap {
            $0 >= 0 && $0 <= Int64(Int.max) ? Int($0) : nil
        }
        let timeRemaining = exactInteger(
            charging == true
                ? properties["AvgTimeToFull"]
                : properties["AvgTimeToEmpty"]
        ).flatMap {
            $0 >= 0 && $0 <= Int64(Int.max) ? Int($0) : nil
        }

        return .success(
            BatteryMetric(
                levelPercent: min(
                    100,
                    max(0, Double(current) / Double(maximum) * 100)
                ),
                powerState: state,
                cycleCount: cycle,
                health: health,
                timeRemainingMinutes: timeRemaining
            )
        )
    }

    static func readSystemProperties()
        -> Result<[String: Any], MetricFailure> {
        switch BatteryTemperatureProvider.readSystemProperties() {
        case let .failure(failure):
            return .failure(failure)
        case let .success(registryProperties):
            var properties = registryProperties
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let sources =
                    IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
                        as? [CFTypeRef] else {
                return .success(properties)
            }
            for source in sources {
                guard let unmanaged = IOPSGetPowerSourceDescription(
                    info,
                    source
                ), let description =
                    unmanaged.takeUnretainedValue() as? [String: Any],
                    description[kIOPSTypeKey as String] as? String
                        == kIOPSInternalBatteryType else {
                    continue
                }
                copy(
                    description,
                    from: kIOPSCurrentCapacityKey,
                    to: "CurrentCapacity",
                    into: &properties
                )
                copy(
                    description,
                    from: kIOPSMaxCapacityKey,
                    to: "MaxCapacity",
                    into: &properties
                )
                copy(
                    description,
                    from: kIOPSIsChargingKey,
                    to: "IsCharging",
                    into: &properties
                )
                copy(
                    description,
                    from: kIOPSBatteryHealthKey,
                    to: "BatteryHealth",
                    into: &properties
                )
                copy(
                    description,
                    from: kIOPSBatteryHealthConditionKey,
                    to: "BatteryHealthCondition",
                    into: &properties
                )
                copy(
                    description,
                    from: kIOPSTimeToEmptyKey,
                    to: "AvgTimeToEmpty",
                    into: &properties
                )
                copy(
                    description,
                    from: kIOPSTimeToFullChargeKey,
                    to: "AvgTimeToFull",
                    into: &properties
                )
                if let state =
                    description[kIOPSPowerSourceStateKey as String] as? String {
                    properties["ExternalConnected"] =
                        state == kIOPSACPowerValue
                }
                break
            }
            return .success(properties)
        }
    }

    private static func copy(
        _ source: [String: Any],
        from key: String,
        to destination: String,
        into target: inout [String: Any]
    ) {
        if let value = source[key] {
            target[destination] = value
        }
    }

    private static func exactInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID() else {
            return nil
        }
        var integer: Int64 = 0
        guard CFNumberGetValue(number, .sInt64Type, &integer),
              number.doubleValue.isFinite,
              number.doubleValue == Double(integer) else {
            return nil
        }
        return integer
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}
