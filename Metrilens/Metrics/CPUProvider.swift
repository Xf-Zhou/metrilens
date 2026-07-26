import Darwin
import Foundation

struct CPUTicks: Equatable {
    let user: UInt64
    let system: UInt64
    let nice: UInt64
    let idle: UInt64
}

protocol CPUProviding: AnyObject {
    var state: MetricState<CPUMetric> { get }
    func resetBaseline()
    func pause(nowUptime: TimeInterval)
    func expireCachedValue(nowUptime: TimeInterval)
    func sample(period: TimeInterval) -> MetricState<CPUMetric>
}

final class CPUProvider: CPUProviding {
    private var previous: CPUTicks?
    private let stateMachine = MetricStateMachine<CPUMetric>()
    private var cacheTTL: TimeInterval = 10

    var state: MetricState<CPUMetric> { stateMachine.state }

    func resetBaseline() {
        previous = nil
    }

    func pause(nowUptime: TimeInterval) {
        previous = nil
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

    func sample(period: TimeInterval) -> MetricState<CPUMetric> {
        cacheTTL = max(10, period * 3)
        switch Self.readTicks() {
        case let .success(current):
            guard let previous else {
                self.previous = current
                return stateMachine.state
            }
            self.previous = current
            guard let percent = Self.utilization(previous: previous, current: current) else {
                return stateMachine.recordFailure(
                    .counterOverflow,
                    failureLimit: 3,
                    ttl: max(10, period * 3)
                )
            }
            return stateMachine.recordSuccess(CPUMetric(percent: percent))
        case let .failure(error):
            return stateMachine.recordFailure(
                error,
                failureLimit: 3,
                ttl: max(10, period * 3)
            )
        }
    }

    static func utilization(previous: CPUTicks, current: CPUTicks) -> Double? {
        guard current.user >= previous.user,
              current.system >= previous.system,
              current.nice >= previous.nice,
              current.idle >= previous.idle else {
            return nil
        }

        let user = current.user - previous.user
        let system = current.system - previous.system
        let nice = current.nice - previous.nice
        let idle = current.idle - previous.idle
        let (firstBusy, overflow1) = user.addingReportingOverflow(system)
        let (busy, overflow2) = firstBusy.addingReportingOverflow(nice)
        let (total, overflow3) = busy.addingReportingOverflow(idle)
        guard !overflow1, !overflow2, !overflow3, total > 0 else { return nil }
        return min(100, max(0, Double(busy) / Double(total) * 100))
    }

    private static func readTicks() -> Result<CPUTicks, MetricFailure> {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .failure(.machFailure(result))
        }

        return .success(
            CPUTicks(
                user: UInt64(info.cpu_ticks.0),
                system: UInt64(info.cpu_ticks.1),
                nice: UInt64(info.cpu_ticks.3),
                idle: UInt64(info.cpu_ticks.2)
            )
        )
    }
}
