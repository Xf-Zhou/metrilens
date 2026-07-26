import Foundation

struct SampleStamp: Equatable {
    let wallTime: Date
    let uptime: TimeInterval

    static func now() -> SampleStamp {
        SampleStamp(wallTime: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    }
}

enum MetricFailure: Error, Equatable {
    case noHardware
    case fieldMissing
    case unsupportedEncoding
    case counterOverflow
    case outOfRange
    case outlierJump
    case iokitFailure(Int32)
    case machFailure(Int32)
}

enum MetricState<Value> {
    case available(Value, SampleStamp)
    case stale(Value, SampleStamp)
    case unavailable(MetricFailure)
    case unsupported(MetricFailure)

    var value: Value? {
        switch self {
        case let .available(value, _), let .stale(value, _):
            return value
        case .unavailable, .unsupported:
            return nil
        }
    }

    var stamp: SampleStamp? {
        switch self {
        case let .available(_, stamp), let .stale(_, stamp):
            return stamp
        case .unavailable, .unsupported:
            return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

final class MetricStateMachine<Value> {
    private(set) var state: MetricState<Value>
    private var lastSuccess: (Value, SampleStamp)?
    private var consecutiveFailures = 0
    private var lastFailure: MetricFailure?

    init(initialFailure: MetricFailure = .fieldMissing) {
        state = .unavailable(initialFailure)
    }

    @discardableResult
    func recordSuccess(_ value: Value, stamp: SampleStamp = .now()) -> MetricState<Value> {
        consecutiveFailures = 0
        lastFailure = nil
        lastSuccess = (value, stamp)
        state = .available(value, stamp)
        return state
    }

    @discardableResult
    func recordFailure(
        _ failure: MetricFailure,
        nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        failureLimit: Int,
        ttl: TimeInterval
    ) -> MetricState<Value> {
        consecutiveFailures += 1
        lastFailure = failure
        if let lastSuccess,
           consecutiveFailures < failureLimit,
           nowUptime - lastSuccess.1.uptime < ttl {
            state = .stale(lastSuccess.0, lastSuccess.1)
        } else {
            state = .unavailable(failure)
            lastSuccess = nil
        }
        return state
    }

    @discardableResult
    func recordUnsupported(_ failure: MetricFailure) -> MetricState<Value> {
        consecutiveFailures = 0
        lastFailure = failure
        lastSuccess = nil
        state = .unsupported(failure)
        return state
    }

    func reset(_ failure: MetricFailure = .fieldMissing) {
        consecutiveFailures = 0
        lastFailure = failure
        lastSuccess = nil
        state = .unavailable(failure)
    }

    @discardableResult
    func preserveFreshValueAsStale(
        nowUptime: TimeInterval,
        ttl: TimeInterval,
        failure: MetricFailure = .fieldMissing
    ) -> MetricState<Value> {
        guard case .unsupported = state else {
            lastFailure = failure
            consecutiveFailures = max(1, consecutiveFailures)
            if let lastSuccess, nowUptime - lastSuccess.1.uptime < ttl {
                state = .stale(lastSuccess.0, lastSuccess.1)
            } else {
                state = .unavailable(failure)
                lastSuccess = nil
            }
            return state
        }
        return state
    }

    @discardableResult
    func presentProvisionalStale(
        _ value: Value,
        stamp: SampleStamp
    ) -> MetricState<Value> {
        state = .stale(value, stamp)
        return state
    }

    @discardableResult
    func presentProvisionalUnavailable(
        _ failure: MetricFailure
    ) -> MetricState<Value> {
        state = .unavailable(failure)
        return state
    }

    @discardableResult
    func expireFailedValueIfNeeded(
        nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        ttl: TimeInterval
    ) -> MetricState<Value> {
        guard consecutiveFailures > 0,
              let lastSuccess,
              nowUptime - lastSuccess.1.uptime >= ttl else {
            return state
        }
        state = .unavailable(lastFailure ?? .fieldMissing)
        self.lastSuccess = nil
        return state
    }
}
