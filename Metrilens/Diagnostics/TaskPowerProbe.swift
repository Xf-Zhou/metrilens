import Darwin
import Foundation
import IOKit.ps

struct TaskPowerSnapshot: Codable, Equatable {
    let interruptWakeups: UInt64
    let platformIdleWakeups: UInt64
    let timerWakeupsBin1: UInt64
    let timerWakeupsBin2: UInt64
}

struct TaskPowerReport: Codable {
    let version: Int
    let launchToken: String
    let processID: Int32
    let requestedStartUptime: TimeInterval
    let startedAtUptime: TimeInterval
    let endedAtUptime: TimeInterval
    let startReadBeganAtUptime: TimeInterval
    let startReadEndedAtUptime: TimeInterval
    let endReadBeganAtUptime: TimeInterval
    let endReadEndedAtUptime: TimeInterval
    let start: TaskPowerSnapshot
    let end: TaskPowerSnapshot
    let startContext: PerformanceRuntimeContext
    let endContext: PerformanceRuntimeContext
    let interruptWakeupsPerSecond: Double
}

struct TimedTaskPowerSnapshot {
    let snapshot: TaskPowerSnapshot
    let readBeganAtUptime: TimeInterval
    let readEndedAtUptime: TimeInterval

    var midpointUptime: TimeInterval {
        (readBeganAtUptime + readEndedAtUptime) / 2
    }
}

struct PerformanceRuntimeContext: Codable {
    let primaryMetric: String
    let configuredInterval: TimeInterval
    let effectiveInterval: TimeInterval
    let lowPowerModeEnabled: Bool
    let powerSource: String
}

enum TaskPowerProbeError: Error {
    case machFailure(kern_return_t)
    case shortStructure(expected: mach_msg_type_number_t, actual: mach_msg_type_number_t)
    case counterReset
    case invalidDuration
    case invalidFileDescriptor
    case encodingFailure
}

final class TaskPowerProbe {
    private static let maximumEndpointDeviation: TimeInterval = 0.1
    private let reportFileDescriptor: Int32
    private let launchToken: String
    private let requestedStartUptime: TimeInterval
    private let queue = DispatchQueue(label: "com.xfzhou.Metrilens.performance-probe", qos: .utility)
    private let preferences: PreferencesSnapshot
    private let effectiveCPUPeriodProvider: () -> TimeInterval?
    private var startSnapshot: TaskPowerSnapshot?
    private var startContext: PerformanceRuntimeContext?
    private var startUptime: TimeInterval?
    private var startReadBeganAtUptime: TimeInterval?
    private var startReadEndedAtUptime: TimeInterval?

    private init(
        reportFileDescriptor: Int32,
        launchToken: String,
        requestedStartUptime: TimeInterval,
        preferences: PreferencesSnapshot,
        effectiveCPUPeriodProvider: @escaping () -> TimeInterval?
    ) {
        self.reportFileDescriptor = reportFileDescriptor
        self.launchToken = launchToken
        self.requestedStartUptime = requestedStartUptime
        self.preferences = preferences
        self.effectiveCPUPeriodProvider = effectiveCPUPeriodProvider
    }

    static func startIfRequested(
        preferences: PreferencesSnapshot,
        effectiveCPUPeriodProvider: @escaping () -> TimeInterval?
    ) -> TaskPowerProbe? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["METRILENS_PERF_MODE"] == "1",
              let descriptorText = environment["METRILENS_PERF_REPORT_FD"],
              let descriptor = Int32(descriptorText),
              descriptor >= 0,
              let token = environment["METRILENS_PERF_LAUNCH_TOKEN"],
              !token.isEmpty else {
            return nil
        }
        guard let requestedStartUptime = validatedRequestedStartUptime(
            environment["METRILENS_PERF_START_UPTIME"],
            nowUptime: ProcessInfo.processInfo.systemUptime
        ) else {
            Darwin.close(descriptor)
            return nil
        }
        let probe = TaskPowerProbe(
            reportFileDescriptor: descriptor,
            launchToken: token,
            requestedStartUptime: requestedStartUptime,
            preferences: preferences,
            effectiveCPUPeriodProvider: effectiveCPUPeriodProvider
        )
        probe.schedule()
        return probe
    }

    static func signalReadyIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let descriptorText = environment["METRILENS_PERF_READY_FD"],
              let descriptor = Int32(descriptorText),
              descriptor >= 0 else {
            return
        }
        let token = environment["METRILENS_PERF_READY_TOKEN"] ?? "METRILENS_READY"
        _ = writeLine(token, to: descriptor)
        Darwin.close(descriptor)
    }

    static func calculateRate(
        start: TaskPowerSnapshot,
        end: TaskPowerSnapshot,
        elapsed: TimeInterval
    ) -> Result<Double, TaskPowerProbeError> {
        guard elapsed > 0, elapsed.isFinite else {
            return .failure(.invalidDuration)
        }
        guard end.interruptWakeups >= start.interruptWakeups else {
            return .failure(.counterReset)
        }
        return .success(Double(end.interruptWakeups - start.interruptWakeups) / elapsed)
    }

    static func validatedRequestedStartUptime(
        _ value: String?,
        nowUptime: TimeInterval
    ) -> TimeInterval? {
        guard let value,
              let requested = TimeInterval(value),
              requested.isFinite,
              requested > nowUptime else {
            return nil
        }
        return requested
    }

    static func readCurrentTask() -> Result<TaskPowerSnapshot, TaskPowerProbeError> {
        var info = task_power_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_power_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let expected = count
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(expected)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .failure(.machFailure(result))
        }
        guard count >= expected else {
            return .failure(.shortStructure(expected: expected, actual: count))
        }
        return .success(
            TaskPowerSnapshot(
                interruptWakeups: info.task_interrupt_wakeups,
                platformIdleWakeups: info.task_platform_idle_wakeups,
                timerWakeupsBin1: info.task_timer_wakeups_bin_1,
                timerWakeupsBin2: info.task_timer_wakeups_bin_2
            )
        )
    }

    static func readTimedCurrentTask(
        clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        reader: () -> Result<TaskPowerSnapshot, TaskPowerProbeError> = {
            TaskPowerProbe.readCurrentTask()
        }
    ) -> Result<TimedTaskPowerSnapshot, TaskPowerProbeError> {
        let began = clock()
        let result = reader()
        let ended = clock()
        return result.map {
            TimedTaskPowerSnapshot(
                snapshot: $0,
                readBeganAtUptime: began,
                readEndedAtUptime: ended
            )
        }
    }

    static func endpointContainsSnapshot(
        _ timed: TimedTaskPowerSnapshot,
        expectedUptime: TimeInterval,
        tolerance: TimeInterval = maximumEndpointDeviation
    ) -> Bool {
        timed.readEndedAtUptime >= timed.readBeganAtUptime
            && timed.readEndedAtUptime - timed.readBeganAtUptime <= tolerance
            && abs(timed.readBeganAtUptime - expectedUptime) <= tolerance
            && abs(timed.readEndedAtUptime - expectedUptime) <= tolerance
    }

    private func schedule() {
        let delay = requestedStartUptime - ProcessInfo.processInfo.systemUptime
        guard delay > 0 else {
            Darwin.close(reportFileDescriptor)
            return
        }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            switch Self.readTimedCurrentTask() {
            case let .success(timed):
                guard Self.endpointContainsSnapshot(
                    timed,
                    expectedUptime: self.requestedStartUptime
                ) else {
                    Darwin.close(self.reportFileDescriptor)
                    return
                }
                self.startSnapshot = timed.snapshot
                self.startUptime = timed.midpointUptime
                self.startReadBeganAtUptime = timed.readBeganAtUptime
                self.startReadEndedAtUptime = timed.readEndedAtUptime
                self.queue.asyncAfter(deadline: .now() + 600) { [weak self] in
                    self?.finish()
                }
                self.startContext = self.runtimeContext()
            case .failure:
                Darwin.close(self.reportFileDescriptor)
            }
        }
    }

    private func finish() {
        guard let startSnapshot,
              let startContext,
              let startUptime,
              let startReadBeganAtUptime,
              let startReadEndedAtUptime else {
            Darwin.close(reportFileDescriptor)
            return
        }
        guard case let .success(timedEnd) = Self.readTimedCurrentTask(),
              Self.endpointContainsSnapshot(
                  timedEnd,
                  expectedUptime: requestedStartUptime + 600
              ),
              case let .success(rate) = Self.calculateRate(
                start: startSnapshot,
                end: timedEnd.snapshot,
                elapsed: timedEnd.midpointUptime - startUptime
              ) else {
            Darwin.close(reportFileDescriptor)
            return
        }

        let report = TaskPowerReport(
            version: 3,
            launchToken: launchToken,
            processID: getpid(),
            requestedStartUptime: requestedStartUptime,
            startedAtUptime: startUptime,
            endedAtUptime: timedEnd.midpointUptime,
            startReadBeganAtUptime: startReadBeganAtUptime,
            startReadEndedAtUptime: startReadEndedAtUptime,
            endReadBeganAtUptime: timedEnd.readBeganAtUptime,
            endReadEndedAtUptime: timedEnd.readEndedAtUptime,
            start: startSnapshot,
            end: timedEnd.snapshot,
            startContext: startContext,
            endContext: runtimeContext(),
            interruptWakeupsPerSecond: rate
        )
        guard var data = try? JSONEncoder().encode(report) else {
            Darwin.close(reportFileDescriptor)
            return
        }
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(
                    reportFileDescriptor,
                    base.advanced(by: written),
                    bytes.count - written
                )
                guard result > 0 else { break }
                written += result
            }
        }
        Darwin.close(reportFileDescriptor)
    }

    private func runtimeContext() -> PerformanceRuntimeContext {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        return PerformanceRuntimeContext(
            primaryMetric: preferences.display.primaryMetric.rawValue,
            configuredInterval: preferences.sampling.refreshInterval,
            effectiveInterval: effectiveCPUPeriodProvider() ?? -1,
            lowPowerModeEnabled: lowPower,
            powerSource: Self.currentPowerSource()
        )
    }

    private static func currentPowerSource() -> String {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return "unknown"
        }
        return source as String
    }

    private static func writeLine(_ value: String, to descriptor: Int32) -> Bool {
        guard var data = "\(value)\n".data(using: .utf8) else { return false }
        return data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(descriptor, base.advanced(by: written), bytes.count - written)
                guard result > 0 else { return false }
                written += result
            }
            return true
        }
    }
}
