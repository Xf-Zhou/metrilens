import Darwin
import Foundation
import SystemConfiguration

struct NetworkCounters: Equatable {
    let interfaceName: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let uptime: TimeInterval
}

protocol NetworkProviding: AnyObject {
    var state: MetricState<NetworkMetric> { get }
    var lastSampleFailure: MetricFailure? { get }
    func sample(period: TimeInterval) -> MetricState<NetworkMetric>
    func pause(nowUptime: TimeInterval)
    func resetBaseline()
    func expireCachedValue(nowUptime: TimeInterval)
}

final class NetworkProvider: NetworkProviding {
    typealias CountersReader = () -> Result<NetworkCounters, MetricFailure>

    private let stateMachine = MetricStateMachine<NetworkMetric>()
    private let countersReader: CountersReader
    private var previous: NetworkCounters?
    private var cacheTTL: TimeInterval = 10

    var state: MetricState<NetworkMetric> { stateMachine.state }
    private(set) var lastSampleFailure: MetricFailure?

    init(countersReader: @escaping CountersReader = NetworkProvider.readCounters) {
        self.countersReader = countersReader
    }

    func sample(period: TimeInterval) -> MetricState<NetworkMetric> {
        cacheTTL = max(10, period * 3)
        switch countersReader() {
        case let .success(current):
            guard let previous else {
                self.previous = current
                lastSampleFailure = nil
                return stateMachine.state
            }
            guard previous.interfaceName == current.interfaceName,
                  current.receivedBytes >= previous.receivedBytes,
                  current.sentBytes >= previous.sentBytes,
                  current.uptime > previous.uptime else {
                self.previous = current
                lastSampleFailure = nil
                return stateMachine.preserveFreshValueAsStale(
                    nowUptime: current.uptime,
                    ttl: cacheTTL
                )
            }
            self.previous = current
            let elapsed = current.uptime - previous.uptime
            let download = Double(current.receivedBytes - previous.receivedBytes) / elapsed
            let upload = Double(current.sentBytes - previous.sentBytes) / elapsed
            guard download.isFinite, upload.isFinite else {
                lastSampleFailure = .counterOverflow
                return stateMachine.recordFailure(
                    .counterOverflow,
                    failureLimit: 3,
                    ttl: cacheTTL
                )
            }
            lastSampleFailure = nil
            return stateMachine.recordSuccess(
                NetworkMetric(
                    downloadBytesPerSecond: download,
                    uploadBytesPerSecond: upload,
                    interfaceName: current.interfaceName
                )
            )
        case let .failure(failure):
            previous = nil
            lastSampleFailure = failure
            return stateMachine.recordFailure(
                failure,
                failureLimit: 3,
                ttl: cacheTTL
            )
        }
    }

    func pause(nowUptime: TimeInterval) {
        previous = nil
        _ = stateMachine.preserveFreshValueAsStale(
            nowUptime: nowUptime,
            ttl: cacheTTL
        )
    }

    func resetBaseline() {
        previous = nil
    }

    func expireCachedValue(nowUptime: TimeInterval) {
        _ = stateMachine.expireFailedValueIfNeeded(
            nowUptime: nowUptime,
            ttl: cacheTTL
        )
    }

    static func calculate(
        previous: NetworkCounters,
        current: NetworkCounters
    ) -> NetworkMetric? {
        guard previous.interfaceName == current.interfaceName,
              current.receivedBytes >= previous.receivedBytes,
              current.sentBytes >= previous.sentBytes,
              current.uptime > previous.uptime else {
            return nil
        }
        let elapsed = current.uptime - previous.uptime
        return NetworkMetric(
            downloadBytesPerSecond:
                Double(current.receivedBytes - previous.receivedBytes) / elapsed,
            uploadBytesPerSecond:
                Double(current.sentBytes - previous.sentBytes) / elapsed,
            interfaceName: current.interfaceName
        )
    }

    private static func readCounters() -> Result<NetworkCounters, MetricFailure> {
        guard let store = SCDynamicStoreCreate(
            nil,
            "Metrilens" as CFString,
            nil,
            nil
        ) else {
            return .failure(.noActiveInterface)
        }
        let globalIPv4 = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Global/IPv4" as CFString
        ) as? [String: Any]
        let globalIPv6 = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Global/IPv6" as CFString
        ) as? [String: Any]
        guard let interfaceName = primaryInterface(
            ipv4: globalIPv4,
            ipv6: globalIPv6
        ) else {
            return .failure(.noActiveInterface)
        }

        let interfaceIndex = if_nametoindex(interfaceName)
        guard interfaceIndex != 0 else {
            return .failure(.noActiveInterface)
        }

        var mib = [
            Int32(CTL_NET),
            Int32(PF_ROUTE),
            0,
            0,
            Int32(NET_RT_IFLIST2),
            0
        ]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0,
              length > 0 else {
            return .failure(.fileSystemFailure(errno))
        }
        var messages = [UInt8](repeating: 0, count: length)
        let readResult = messages.withUnsafeMutableBytes { buffer in
            sysctl(
                &mib,
                UInt32(mib.count),
                buffer.baseAddress,
                &length,
                nil,
                0
            )
        }
        guard readResult == 0 else {
            return .failure(.fileSystemFailure(errno))
        }
        guard let counters = counters(
            in: messages,
            byteCount: length,
            interfaceIndex: interfaceIndex,
            interfaceName: interfaceName,
            uptime: ProcessInfo.processInfo.systemUptime
        ) else {
            return .failure(.noActiveInterface)
        }
        return .success(counters)
    }

    static func primaryInterface(
        ipv4: [String: Any]?,
        ipv6: [String: Any]?
    ) -> String? {
        let key = kSCDynamicStorePropNetPrimaryInterface as String
        return ipv4?[key] as? String ?? ipv6?[key] as? String
    }

    static func counters(
        in messages: [UInt8],
        byteCount: Int,
        interfaceIndex: UInt32,
        interfaceName: String,
        uptime: TimeInterval
    ) -> NetworkCounters? {
        let validCount = min(byteCount, messages.count)
        var offset = 0
        while offset + 4 <= validCount {
            let messageLength = Int(messages[offset])
                | (Int(messages[offset + 1]) << 8)
            guard messageLength >= 4,
                  offset + messageLength <= validCount else {
                return nil
            }
            let messageType = messages[offset + 3]
            if messageType == UInt8(RTM_IFINFO2),
               messageLength >= MemoryLayout<if_msghdr2>.size {
                let header = messages.withUnsafeBytes {
                    $0.loadUnaligned(
                        fromByteOffset: offset,
                        as: if_msghdr2.self
                    )
                }
                if UInt32(header.ifm_index) == interfaceIndex {
                    return NetworkCounters(
                        interfaceName: interfaceName,
                        receivedBytes: header.ifm_data.ifi_ibytes,
                        sentBytes: header.ifm_data.ifi_obytes,
                        uptime: uptime
                    )
                }
            }
            offset += messageLength
        }
        return nil
    }
}
