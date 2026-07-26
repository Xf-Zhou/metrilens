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

enum BatteryPowerState: String, Equatable {
    case charging
    case charged
    case discharging
    case externalPower
    case unknown
}

enum BatteryHealth: String, Equatable {
    case good
    case fair
    case poor
    case serviceRecommended
    case unknown
}

struct BatteryMetric: Equatable {
    let levelPercent: Double
    let powerState: BatteryPowerState
    let cycleCount: Int?
    let health: BatteryHealth
    let timeRemainingMinutes: Int?
}

struct NetworkMetric: Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let interfaceName: String
}

struct DiskCapacityMetric: Equatable {
    let totalBytes: UInt64
    let freeBytes: UInt64
    let availableBytes: UInt64

    var usedBytes: UInt64 {
        totalBytes >= freeBytes ? totalBytes - freeBytes : 0
    }

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    var freePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(availableBytes) / Double(totalBytes) * 100
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
    var battery: MetricState<BatteryMetric>
    var batteryTemperature: MetricState<Double>
    var batterySessionMaximumTemperature: MetricState<Double>
    var batteryMaximumTemperature: MetricState<Double>
    var network: MetricState<NetworkMetric>
    var disk: MetricState<DiskCapacityMetric>
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
            battery: .unavailable(.fieldMissing),
            batteryTemperature: .unavailable(.fieldMissing),
            batterySessionMaximumTemperature: .unavailable(.fieldMissing),
            batteryMaximumTemperature: .unavailable(.fieldMissing),
            network: .unavailable(.fieldMissing),
            disk: .unavailable(.fieldMissing),
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
