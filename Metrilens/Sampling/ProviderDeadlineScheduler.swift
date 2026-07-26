import Foundation

enum ProviderID: Hashable {
    case cpu
    case memory
    case battery
    case network
    case disk
}

struct SchedulerDebugState {
    let activeTimerCount: Int
    let inFlightProviders: Set<ProviderID>
    let scheduledProviders: Set<ProviderID>
    let deadlines: [ProviderID: UInt64]
    let lastRuns: [ProviderID: UInt64]
}

final class ProviderDeadlineScheduler {
    typealias DueHandler = (Set<ProviderID>) -> Void

    private let queue: DispatchQueue
    private let dueHandler: DueHandler
    private var timer: DispatchSourceTimer?
    private var periods: [ProviderID: TimeInterval] = [:]
    private var deadlines: [ProviderID: UInt64] = [:]
    private var lastRuns: [ProviderID: UInt64] = [:]
    private var inFlight: Set<ProviderID> = []

    init(queue: DispatchQueue, dueHandler: @escaping DueHandler) {
        self.queue = queue
        self.dueHandler = dueHandler
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }

    func update(periods newPeriods: [ProviderID: TimeInterval], force: Set<ProviderID> = []) {
        dispatchPrecondition(condition: .onQueue(queue))
        let now = DispatchTime.now().uptimeNanoseconds
        let removed = Set(periods.keys).subtracting(newPeriods.keys)
        removed.forEach {
            deadlines.removeValue(forKey: $0)
            inFlight.remove($0)
        }
        periods = newPeriods

        for (provider, period) in newPeriods {
            guard !inFlight.contains(provider) else { continue }
            if force.contains(provider) {
                deadlines[provider] = now
            } else if let lastRun = lastRuns[provider] {
                let interval = Self.nanoseconds(period)
                deadlines[provider] = max(now, lastRun.addingReportingOverflow(interval).partialValue)
            } else if deadlines[provider] == nil {
                deadlines[provider] = now
            }
        }
        armTimer()
    }

    func complete(_ provider: ProviderID) {
        dispatchPrecondition(condition: .onQueue(queue))
        inFlight.remove(provider)
        guard let period = periods[provider], let lastRun = lastRuns[provider] else {
            deadlines.removeValue(forKey: provider)
            armTimer()
            return
        }
        deadlines[provider] = lastRun &+ Self.nanoseconds(period)
        armTimer()
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        periods.removeAll()
        deadlines.removeAll()
        inFlight.removeAll()
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    func debugState() -> SchedulerDebugState {
        dispatchPrecondition(condition: .onQueue(queue))
        return SchedulerDebugState(
            activeTimerCount: timer == nil ? 0 : 1,
            inFlightProviders: inFlight,
            scheduledProviders: Set(deadlines.keys),
            deadlines: deadlines,
            lastRuns: lastRuns
        )
    }

    private func armTimer() {
        guard let earliest = deadlines.values.min() else {
            timer?.schedule(deadline: .distantFuture)
            return
        }

        if timer == nil {
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.setEventHandler { [weak self] in self?.fire() }
            source.resume()
            timer = source
        }

        let shortest = periods.values.min() ?? 1
        let leewaySeconds = min(0.2, shortest * 0.1)
        timer?.schedule(
            deadline: DispatchTime(uptimeNanoseconds: earliest),
            leeway: .nanoseconds(Int(Self.nanoseconds(leewaySeconds)))
        )
    }

    private func fire() {
        dispatchPrecondition(condition: .onQueue(queue))
        let now = DispatchTime.now().uptimeNanoseconds
        let tolerance: UInt64 = 1_000_000
        let due = Set(deadlines.compactMap { provider, deadline in
            deadline <= now &+ tolerance && !inFlight.contains(provider) ? provider : nil
        })
        guard !due.isEmpty else {
            armTimer()
            return
        }

        for provider in due {
            deadlines.removeValue(forKey: provider)
            inFlight.insert(provider)
            lastRuns[provider] = now
        }
        dueHandler(due)
        armTimer()
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
