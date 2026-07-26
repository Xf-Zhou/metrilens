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

struct CPUHistoryPoint: Equatable {
    let uptime: TimeInterval
    let percent: Double
}

struct SystemSnapshot {
    var cpu: MetricState<CPUMetric>
    var memory: MetricState<MemoryMetric>
    var batteryTemperature: MetricState<Double>
    var batteryMaximumTemperature: MetricState<Double>
    var thermalLevel: ThermalLevel
    var cpuHistory: [CPUHistoryPoint]
    var cpuHistoryCollecting: Bool

    static func initial() -> SystemSnapshot {
        SystemSnapshot(
            cpu: .unavailable(.fieldMissing),
            memory: .unavailable(.fieldMissing),
            batteryTemperature: .unavailable(.fieldMissing),
            batteryMaximumTemperature: .unavailable(.fieldMissing),
            thermalLevel: ThermalLevel(ProcessInfo.processInfo.thermalState),
            cpuHistory: [],
            cpuHistoryCollecting: true
        )
    }
}
