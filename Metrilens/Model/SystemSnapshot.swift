import Foundation

struct CPUMetric: Equatable {
    let percent: Double
}

struct MemoryMetric: Equatable {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let availableBytes: UInt64
    let purgeableBytes: UInt64

    var percent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

enum ThermalLevel: Int, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}

struct MetricHistoryPoint: Equatable {
    let uptime: TimeInterval
    let percent: Double
}

typealias CPUHistoryPoint = MetricHistoryPoint

struct SamplingRuntimeState: Equatable {
    var isRunning: Bool
    var isSleeping: Bool
    var isPopoverVisible: Bool
    var effectivePeriods: [ProviderID: TimeInterval]

    static let stopped = SamplingRuntimeState(
        isRunning: false,
        isSleeping: false,
        isPopoverVisible: false,
        effectivePeriods: [:]
    )
}

struct RecentMetricError: Equatable {
    let provider: ProviderID
    let failure: MetricFailure
    let wallTime: Date
}

struct SystemSnapshot {
    var cpu: MetricState<CPUMetric>
    var memory: MetricState<MemoryMetric>
    var batteryTemperature: MetricState<Double>
    var batterySessionMaximumTemperature: MetricState<Double>
    var batteryMaximumTemperature: MetricState<Double>
    var thermalLevel: ThermalLevel
    var cpuHistory: [MetricHistoryPoint]
    var cpuHistoryCollecting: Bool
    var cpuHistorySummary: MetricHistorySummary?
    var memoryHistory: [MetricHistoryPoint]
    var memoryHistoryCollecting: Bool
    var memoryHistorySummary: MetricHistorySummary?
    var samplingRuntime: SamplingRuntimeState
    var recentErrors: [RecentMetricError]

    static func initial() -> SystemSnapshot {
        SystemSnapshot(
            cpu: .unavailable(.fieldMissing),
            memory: .unavailable(.fieldMissing),
            batteryTemperature: .unavailable(.fieldMissing),
            batterySessionMaximumTemperature: .unavailable(.fieldMissing),
            batteryMaximumTemperature: .unavailable(.fieldMissing),
            thermalLevel: ThermalLevel(ProcessInfo.processInfo.thermalState),
            cpuHistory: [],
            cpuHistoryCollecting: true,
            cpuHistorySummary: nil,
            memoryHistory: [],
            memoryHistoryCollecting: true,
            memoryHistorySummary: nil,
            samplingRuntime: .stopped,
            recentErrors: []
        )
    }
}
