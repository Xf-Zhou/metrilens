import Darwin
import Foundation

struct MemoryCounters {
    let internalPages: UInt64
    let wiredPages: UInt64
    let compressorPages: UInt64
    let purgeablePages: UInt64
    let pageSize: UInt64
    let totalBytes: UInt64
}

protocol MemoryProviding: AnyObject {
    var state: MetricState<MemoryMetric> { get }
    var lastSampleFailure: MetricFailure? { get }
    func pause(nowUptime: TimeInterval)
    func expireCachedValue(nowUptime: TimeInterval)
    func sample(period: TimeInterval) -> MetricState<MemoryMetric>
}

final class MemoryProvider: MemoryProviding {
    private let stateMachine = MetricStateMachine<MemoryMetric>()
    private var cacheTTL: TimeInterval = 10

    var state: MetricState<MemoryMetric> { stateMachine.state }
    private(set) var lastSampleFailure: MetricFailure?

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

    func sample(period: TimeInterval) -> MetricState<MemoryMetric> {
        cacheTTL = max(10, period * 3)
        switch Self.readCounters() {
        case let .success(counters):
            switch Self.calculate(counters) {
            case let .success(metric):
                lastSampleFailure = nil
                return stateMachine.recordSuccess(metric)
            case let .failure(error):
                lastSampleFailure = error
                return stateMachine.recordFailure(
                    error,
                    failureLimit: 3,
                    ttl: max(10, period * 3)
                )
            }
        case let .failure(error):
            lastSampleFailure = error
            return stateMachine.recordFailure(
                error,
                failureLimit: 3,
                ttl: max(10, period * 3)
            )
        }
    }

    static func calculate(_ counters: MemoryCounters) -> Result<MemoryMetric, MetricFailure> {
        let (sum1, overflow1) = counters.internalPages.addingReportingOverflow(counters.wiredPages)
        let (occupiedPages, overflow2) = sum1.addingReportingOverflow(counters.compressorPages)
        let (occupiedBytes, overflow3) = occupiedPages.multipliedReportingOverflow(by: counters.pageSize)
        let (purgeableBytes, overflow4) = counters.purgeablePages.multipliedReportingOverflow(by: counters.pageSize)
        guard !overflow1, !overflow2, !overflow3, !overflow4, counters.totalBytes > 0 else {
            return .failure(.counterOverflow)
        }
        let usedBytes = min(occupiedBytes, counters.totalBytes)
        return .success(
            MemoryMetric(
                usedBytes: usedBytes,
                totalBytes: counters.totalBytes,
                availableBytes: counters.totalBytes - usedBytes,
                purgeableBytes: purgeableBytes
            )
        )
    }

    private static func readCounters() -> Result<MemoryCounters, MetricFailure> {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .failure(.machFailure(result))
        }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else {
            return .failure(.machFailure(pageResult))
        }

        return .success(
            MemoryCounters(
                internalPages: UInt64(info.internal_page_count),
                wiredPages: UInt64(info.wire_count),
                compressorPages: UInt64(info.compressor_page_count),
                purgeablePages: UInt64(info.purgeable_count),
                pageSize: UInt64(pageSize),
                totalBytes: ProcessInfo.processInfo.physicalMemory
            )
        )
    }
}
