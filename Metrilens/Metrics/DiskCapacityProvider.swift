import Darwin
import Foundation

protocol DiskCapacityProviding: AnyObject {
    var state: MetricState<DiskCapacityMetric> { get }
    var lastSampleFailure: MetricFailure? { get }
    func sample(period: TimeInterval) -> MetricState<DiskCapacityMetric>
    func pause(nowUptime: TimeInterval)
    func expireCachedValue(nowUptime: TimeInterval)
}

final class DiskCapacityProvider: DiskCapacityProviding {
    typealias CapacityReader =
        () -> Result<DiskCapacityMetric, MetricFailure>

    static let startupVolumeURL = URL(
        fileURLWithPath: "/",
        isDirectory: true
    ).standardizedFileURL

    private let stateMachine = MetricStateMachine<DiskCapacityMetric>()
    private let capacityReader: CapacityReader
    private var cacheTTL: TimeInterval = 180

    var state: MetricState<DiskCapacityMetric> { stateMachine.state }
    private(set) var lastSampleFailure: MetricFailure?

    init(
        capacityReader: @escaping CapacityReader =
            DiskCapacityProvider.readCapacity
    ) {
        self.capacityReader = capacityReader
    }

    func sample(period: TimeInterval) -> MetricState<DiskCapacityMetric> {
        cacheTTL = max(180, period * 3)
        switch capacityReader() {
        case let .success(metric):
            guard metric.totalBytes > 0,
                  metric.freeBytes <= metric.totalBytes,
                  metric.availableBytes <= metric.totalBytes else {
                lastSampleFailure = .outOfRange
                return stateMachine.recordFailure(
                    .outOfRange,
                    failureLimit: 2,
                    ttl: cacheTTL
                )
            }
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

    private static func readCapacity()
        -> Result<DiskCapacityMetric, MetricFailure> {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(
                forPath: startupVolumeURL.path
            )
            guard let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
                  let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
                return .failure(.fieldMissing)
            }
            let available: UInt64
            if #available(macOS 11.0, *) {
                let values = try startupVolumeURL
                    .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                available = values.volumeAvailableCapacityForImportantUsage
                    .flatMap { $0 >= 0 ? UInt64($0) : nil } ?? free
            } else {
                available = free
            }
            return .success(
                DiskCapacityMetric(
                    totalBytes: total,
                    freeBytes: free,
                    availableBytes: min(available, total)
                )
            )
        } catch let error as NSError {
            return .failure(.fileSystemFailure(Int32(error.code)))
        }
    }
}
